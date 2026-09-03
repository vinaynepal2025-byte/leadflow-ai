const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { buildWhatsAppLink } = require('../services/phone');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /whatsapp/chat-link/:leadId?message=...&contact=primary|alternate
// FREE method — no Meta Business API, no cost, no approval needed.
// Returns a wa.me "click to chat" link with the message pre-filled.
// Counselor taps it, WhatsApp opens with the message ready, they hit Send.
// Semi-automatic: the app prepares everything, a human sends the final tap.
//
// contact defaults to 'primary' (lead.phone / lead.phone_country_code); pass
// contact=alternate to build the link from lead.alternate_phone /
// lead.alternate_phone_country_code instead. Same buildWhatsAppLink() either
// way -- only which pair of columns gets read changes.
router.get('/chat-link/:leadId', async (req, res) => {
  const tid = tenantId(req);
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const contact = req.query.contact === 'alternate' ? 'alternate' : 'primary';
  const phone = contact === 'alternate' ? lead.alternate_phone : lead.phone;
  const phoneCountryCode = contact === 'alternate' ? lead.alternate_phone_country_code : lead.phone_country_code;

  if (!phone) {
    return res.status(400).json({
      error: contact === 'alternate'
        ? 'This lead has no alternate phone number on file'
        : 'This lead has no phone number on file',
    });
  }

  const message = req.query.message || `Hi ${lead.full_name}, this is regarding your enquiry.`;
  // The national number and its country code are stored in separate
  // columns (falling back to the tenant default). Building the link from
  // the phone digits alone produced an unroutable wa.me number.
  const tenant = await db.prepare('SELECT default_country_code FROM tenants WHERE id = ?').get(tid);
  const link = buildWhatsAppLink(
    phone,
    phoneCountryCode,
    message,
    tenant && tenant.default_country_code,
  );
  if (!link) return res.status(400).json({ error: 'Could not build a WhatsApp link for this number' });

  res.json({ lead_id: lead.id, phone, contact, chat_link: link, message });
});

// POST /whatsapp/chat-link/:leadId/confirm-sent
// Call this after the counselor taps Send in WhatsApp, to log it in
// Communication Hub — since the free wa.me method has no delivery webhook
// of its own, the app can't know automatically that it was sent.
router.post('/chat-link/:leadId/confirm-sent', async (req, res) => {
  const tid = tenantId(req);
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const { message, created_by } = req.body;
  const id = randomUUID();
  await db.prepare(`
    INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
    VALUES (?, ?, ?, 'whatsapp-link', 'outbound', ?, ?)
  `).run(id, tid, lead.id, message || null, created_by || null);

  res.status(201).json(await db.prepare('SELECT * FROM communications WHERE id = ?').get(id));
});

module.exports = router;
