const express = require('express');
const { randomUUID } = require('crypto');
const QRCode = require('qrcode');
const db = require('../db');
const { createNotification } = require('./notifications');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// Builds a standard UPI "intent" deep link. Opening this on Android/iOS
// hands off to whichever UPI app the person already has (GPay, PhonePe,
// Paytm, BHIM, ...) with the payee, amount, and note pre-filled -- the
// person completes payment inside their own trusted app. LeadFlow never
// touches the money: it goes straight to the provider's own UPI ID, which
// is also why this needs no payment-gateway approval to go live.
function buildUpiLink({ upiId, payeeName, amount, note }) {
  const parts = {
    pa: upiId,
    pn: payeeName,
    am: amount.toFixed(2),
    cu: 'INR',
    tn: note,
  };
  // encodeURIComponent (not URLSearchParams) so spaces become %20, not +.
  // Both are technically valid, but some UPI apps parse the query string
  // strictly and mis-handle "+" in the payee name / note fields.
  const query = Object.entries(parts)
    .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
    .join('&');
  return `upi://pay?${query}`;
}

// GET /peer-reviews?lead_id=xxx  |  ?provider_id=xxx
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, provider_id } = req.query;

  let query = `SELECT b.*, rp.full_name AS provider_name, rp.upi_id AS provider_upi, c.name AS college_name
               FROM peer_review_bookings b
               JOIN review_providers rp ON rp.id = b.provider_id
               JOIN colleges c ON c.id = b.college_id
               WHERE b.tenant_id = ?`;
  const params = [tid];
  if (lead_id) { query += ' AND b.lead_id = ?'; params.push(lead_id); }
  if (provider_id) { query += ' AND b.provider_id = ?'; params.push(provider_id); }
  query += ' ORDER BY b.created_at DESC';

  res.json(await db.prepare(query).all(...params));
});

// POST /peer-reviews — book a paid review call. Validates the college has
// peer review switched on (per-college toggle), the provider is active,
// and returns a ready-to-tap UPI payment link -- no money moves yet.
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, college_id, provider_id } = req.body;
  if (!lead_id || !college_id || !provider_id) {
    return res.status(400).json({ error: 'lead_id, college_id, and provider_id are required' });
  }

  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const college = await db.prepare('SELECT * FROM colleges WHERE tenant_id = ? AND id = ?').get(tid, college_id);
  if (!college) return res.status(404).json({ error: 'College not found' });
  if (!college.peer_review_enabled) {
    return res.status(400).json({ error: `Peer review is not enabled for ${college.name}` });
  }

  const provider = await db.prepare('SELECT * FROM review_providers WHERE tenant_id = ? AND id = ? AND college_id = ?').get(tid, provider_id, college_id);
  if (!provider) return res.status(404).json({ error: 'Review provider not found for this college' });
  if (!provider.active || !provider.verified) {
    return res.status(400).json({ error: 'This provider is not currently accepting bookings' });
  }

  const price = provider.price_per_review ?? college.peer_review_default_price;
  if (!price) return res.status(400).json({ error: 'No price is set for this provider or college -- set one before booking' });

  const id = randomUUID();
  const commissionPercent = college.commission_percent || 0;
  await db.prepare(`
    INSERT INTO peer_review_bookings (id, tenant_id, lead_id, college_id, provider_id, price, commission_percent, payment_status, status)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', 'booked')
  `).run(id, tid, lead_id, college_id, provider_id, price, commissionPercent);

  const upiLink = buildUpiLink({
    upiId: provider.upi_id,
    payeeName: provider.full_name,
    amount: price,
    note: `Review call - ${college.name}`,
  });

  res.status(201).json({
    booking: await db.prepare('SELECT * FROM peer_review_bookings WHERE id = ?').get(id),
    upi_payment_link: upiLink,
    // The counselor's own phone is NOT who should pay -- the lead is. This
    // is a public, no-login page (booking id is an unguessable UUID, same
    // honor-system trust level as the WhatsApp chat-link flow) that the
    // lead opens on THEIR OWN phone via a WhatsApp share, no app needed.
    public_pay_url: `${req.protocol}://${req.get('host')}/peer-reviews/pay/${id}`,
    provider_name: provider.full_name,
    college_name: college.name,
  });
});

// Shared by both confirm paths below: the in-app one (counselor, tenant
// header available) and the public pay-page one (the lead, no tenant
// header -- their browser has no way to send one). Marks the booking
// paid, auto-creates the actual Meeting record so the call lives in the
// normal Meetings & Campus Tours flow, and notifies the counselor.
async function markBookingPaid(booking, paymentNote) {
  const provider = await db.prepare('SELECT * FROM review_providers WHERE id = ?').get(booking.provider_id);
  const college = await db.prepare('SELECT * FROM colleges WHERE id = ?').get(booking.college_id);

  const meetingId = randomUUID();
  await db.prepare(`
    INSERT INTO meetings (id, tenant_id, lead_id, meeting_type, title, scheduled_at, mode, host_name, status, requested_by)
    VALUES (?, ?, ?, 'Peer Review Call', ?, datetime('now'), 'online', ?, 'scheduled', 'student')
  `).run(meetingId, booking.tenant_id, booking.lead_id, `Paid review call - ${college?.name || ''}`, provider?.full_name || null);

  await db.prepare(`
    UPDATE peer_review_bookings
    SET payment_status = 'paid', payment_confirmed_at = datetime('now'), payment_note = ?, meeting_id = ?
    WHERE id = ?
  `).run(paymentNote || null, meetingId, booking.id);

  await createNotification(booking.tenant_id, {
    title: 'Peer review payment confirmed',
    body: `${provider?.full_name || 'Provider'} — ${college?.name || ''} — ₹${booking.price}`,
    linkType: 'lead',
    linkId: booking.lead_id,
  });

  return { booking: await db.prepare('SELECT * FROM peer_review_bookings WHERE id = ?').get(booking.id), provider, college };
}

// POST /peer-reviews/:id/confirm-payment — the counselor taps this inside
// the app after the lead says they've paid (there is no server-side
// webhook for a peer-to-peer UPI intent payment, same honest-confirmation
// pattern already used for the free WhatsApp chat-link flow).
router.post('/:id/confirm-payment', async (req, res) => {
  const tid = tenantId(req);
  const booking = await db.prepare('SELECT * FROM peer_review_bookings WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!booking) return res.status(404).json({ error: 'Booking not found' });
  if (booking.payment_status === 'paid') return res.status(400).json({ error: 'Already marked paid' });

  const { booking: updated } = await markBookingPaid(booking, req.body.payment_note);
  res.json(updated);
});

// Renders the public, no-login pay page (mobile-first, zero JS required).
function renderPayPage({ error, paid, provider, college, booking, upiLink, qrDataUrl }) {
  const shell = (body) => `<!DOCTYPE html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>LeadFlow AI — Payment</title></head>
    <body style="font-family:-apple-system,Roboto,sans-serif;background:#f7f8fa;color:#1B2A4A;margin:0;padding:24px;display:flex;justify-content:center;">
      <div style="max-width:420px;width:100%;">${body}</div>
    </body></html>`;

  if (error) {
    return shell(`<div style="background:#fff;border-radius:16px;padding:28px;text-align:center;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
      <div style="font-size:40px;">⚠️</div><h2>${error}</h2></div>`);
  }
  if (paid) {
    return shell(`<div style="background:#fff;border-radius:16px;padding:28px;text-align:center;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
      <div style="font-size:48px;">✅</div>
      <h2 style="margin:8px 0;">Payment confirmed</h2>
      <p style="color:#555;">Your review call with <b>${provider.full_name}</b> (${college.name}) is booked. They'll reach out to you shortly.</p>
    </div>`);
  }
  return shell(`
    <h2 style="margin-bottom:4px;">Review call with ${provider.full_name}</h2>
    <p style="color:#666;margin-top:0;">${college.name}</p>
    <div style="background:#fff;border-radius:16px;padding:20px;box-shadow:0 2px 12px rgba(0,0,0,0.08);text-align:center;">
      <p style="font-size:13px;color:#888;margin-bottom:2px;">Amount</p>
      <p style="font-size:32px;font-weight:700;margin:0 0 18px;">₹${Number(booking.price).toFixed(2)}</p>
      <img src="${qrDataUrl}" alt="UPI QR code" style="width:200px;height:200px;margin-bottom:16px;" />
      <a href="${upiLink}" style="display:block;background:#1B2A4A;color:#fff;padding:14px;border-radius:10px;text-decoration:none;font-weight:600;margin-bottom:12px;">Pay ₹${Number(booking.price).toFixed(2)} via UPI</a>
      <p style="font-size:12px;color:#999;margin:0 0 16px;">Opens GPay, PhonePe, Paytm, or any UPI app on this phone. On a laptop? Scan the QR above with any UPI app instead.</p>
      <form method="POST" action="/peer-reviews/pay/${booking.id}/confirm">
        <button type="submit" style="width:100%;background:#fff;color:#1B2A4A;border:2px solid #1B2A4A;padding:12px;border-radius:10px;font-weight:600;font-size:15px;">I've Paid</button>
      </form>
    </div>
    <p style="font-size:11px;color:#999;text-align:center;margin-top:16px;">Payment goes directly to ${provider.full_name}'s own UPI ID. LeadFlow never touches this money.</p>
  `);
}

// GET /peer-reviews/pay/:id — the actual link shared with the lead over
// WhatsApp. No login, no app, no tenant header (a plain browser navigation
// can't send one) -- looked up by booking id alone, the same unguessable-
// token trust model already used for the WhatsApp chat-link short links.
router.get('/pay/:id', async (req, res) => {
  const booking = await db.prepare('SELECT * FROM peer_review_bookings WHERE id = ?').get(req.params.id);
  if (!booking) return res.status(404).send(renderPayPage({ error: 'This payment link is invalid or has expired.' }));

  const provider = await db.prepare('SELECT * FROM review_providers WHERE id = ?').get(booking.provider_id);
  const college = await db.prepare('SELECT * FROM colleges WHERE id = ?').get(booking.college_id);
  if (!provider || !college) return res.status(404).send(renderPayPage({ error: 'This payment link is invalid or has expired.' }));

  if (booking.payment_status === 'paid') {
    return res.send(renderPayPage({ paid: true, provider, college }));
  }

  const upiLink = buildUpiLink({
    upiId: provider.upi_id,
    payeeName: provider.full_name,
    amount: booking.price,
    note: `Review call - ${college.name}`,
  });
  const qrDataUrl = await QRCode.toDataURL(upiLink, { width: 320, margin: 2 });

  res.send(renderPayPage({ provider, college, booking, upiLink, qrDataUrl }));
});

// POST /peer-reviews/pay/:id/confirm — the lead taps "I've Paid" on the
// public page itself. Plain HTML form POST (no JS dependency) with a
// POST -> redirect -> GET back to the same page, now showing the paid state.
router.post('/pay/:id/confirm', async (req, res) => {
  const booking = await db.prepare('SELECT * FROM peer_review_bookings WHERE id = ?').get(req.params.id);
  if (!booking) return res.status(404).send('Booking not found');
  if (booking.payment_status !== 'paid') {
    await markBookingPaid(booking, 'Confirmed by lead via public pay page');
  }
  res.redirect(`/peer-reviews/pay/${req.params.id}`);
});

// PATCH /peer-reviews/:id/complete — after the call happens: capture rating
// + notes, close the booking, and roll the rating into the provider's
// running average (surfaced back on GET /review-providers).
router.patch('/:id/complete', async (req, res) => {
  const tid = tenantId(req);
  const booking = await db.prepare('SELECT * FROM peer_review_bookings WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!booking) return res.status(404).json({ error: 'Booking not found' });

  const { rating, review_notes } = req.body;
  if (rating !== undefined && (rating < 1 || rating > 5)) {
    return res.status(400).json({ error: 'rating must be between 1 and 5' });
  }

  await db.prepare(`UPDATE peer_review_bookings SET status = 'completed', rating = ?, review_notes = ? WHERE id = ?`)
    .run(rating ?? null, review_notes || null, booking.id);

  if (rating !== undefined) {
    await db.prepare(`UPDATE review_providers SET rating_sum = rating_sum + ?, rating_count = rating_count + 1 WHERE id = ?`)
      .run(rating, booking.provider_id);
  }

  res.json(await db.prepare('SELECT * FROM peer_review_bookings WHERE id = ?').get(booking.id));
});

module.exports = router;
