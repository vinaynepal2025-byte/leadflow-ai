const express = require('express');
const { randomUUID } = require('crypto');
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
  const params = new URLSearchParams({
    pa: upiId,
    pn: payeeName,
    am: amount.toFixed(2),
    cu: 'INR',
    tn: note,
  });
  return `upi://pay?${params.toString()}`;
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
    provider_name: provider.full_name,
    college_name: college.name,
  });
});

// POST /peer-reviews/:id/confirm-payment — the person taps this after
// completing payment in their own UPI app (there is no server-side webhook
// for a peer-to-peer UPI intent payment, same honest-confirmation pattern
// already used for the free WhatsApp chat-link flow). Also auto-creates
// the actual Meeting record so the call itself lives in the normal
// Meetings & Campus Tours flow from here on.
router.post('/:id/confirm-payment', async (req, res) => {
  const tid = tenantId(req);
  const booking = await db.prepare('SELECT * FROM peer_review_bookings WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!booking) return res.status(404).json({ error: 'Booking not found' });
  if (booking.payment_status === 'paid') return res.status(400).json({ error: 'Already marked paid' });

  const provider = await db.prepare('SELECT * FROM review_providers WHERE id = ?').get(booking.provider_id);
  const college = await db.prepare('SELECT * FROM colleges WHERE id = ?').get(booking.college_id);

  const meetingId = randomUUID();
  await db.prepare(`
    INSERT INTO meetings (id, tenant_id, lead_id, meeting_type, title, scheduled_at, mode, host_name, status, requested_by)
    VALUES (?, ?, ?, 'Peer Review Call', ?, datetime('now'), 'online', ?, 'scheduled', 'student')
  `).run(meetingId, tid, booking.lead_id, `Paid review call - ${college?.name || ''}`, provider?.full_name || null);

  await db.prepare(`
    UPDATE peer_review_bookings
    SET payment_status = 'paid', payment_confirmed_at = datetime('now'), payment_note = ?, meeting_id = ?
    WHERE id = ?
  `).run(req.body.payment_note || null, meetingId, booking.id);

  await createNotification(tid, {
    title: 'Peer review payment confirmed',
    body: `${provider?.full_name || 'Provider'} — ${college?.name || ''} — ₹${booking.price}`,
    linkType: 'lead',
    linkId: booking.lead_id,
  });

  res.json(await db.prepare('SELECT * FROM peer_review_bookings WHERE id = ?').get(booking.id));
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
