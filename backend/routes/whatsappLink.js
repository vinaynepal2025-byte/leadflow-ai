const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { buildWhatsAppLink } = require('../services/phone');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /whatsapp/chat-link/:leadId?message=... 
// FREE method — no Meta Business API, no cost, no approval needed.
// Returns a wa.me "click to chat" link with the message pre-filled.
// Counselor taps it, WhatsApp opens with the message ready, they hit Send.
// Semi-automatic: the app prepares everything, a human sends the final tap.
router.get('/chat-link/:leadId', async (req, res) => {
  const tid = tenantId(req);
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });
  if (!lead.phone) return res.status(400).json({ error: 'This lead has no phone number on file' });

  const message = req.query.message || `Hi ${lead.full_name}, this is regarding your enquiry.`;
  // leads.phone is the national number; the country code lives in
  // leads.phone_country_code (falling back to the tenant default). Building
  // the link from lead.phone alone produced an unroutable wa.me number.
  const tenant = await db.prepare('SELECT default_country_code FROM tenants WHERE id = ?').get(tid);
  const link = buildWhatsAppLink(
    lead.phone,
    lead.phone_country_code,
    message,
    tenant && tenant.default_country_code,
  );
  if (!link) return res.status(400).json({ error: 'Could not build a WhatsApp link for this number' });

  res.json({ lead_id: lead.id, phone: lead.phone, chat_link: link, message });
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
