const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { sendWhatsAppMessage } = require('../services/whatsapp');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// POST /whatsapp/send  { lead_id, message, created_by }
// Sends via Meta's WhatsApp Cloud API AND logs it in Communication Hub automatically.
router.post('/send', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, message, created_by } = req.body;

  if (!lead_id || !message) {
    return res.status(400).json({ error: 'lead_id and message are required' });
  }

  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });
  if (!lead.phone) return res.status(400).json({ error: 'This lead has no phone number on file' });

  try {
    await sendWhatsAppMessage(lead.phone, message);
  } catch (err) {
    // Still return a clear error to the app — but don't silently fail
    return res.status(502).json({ error: err.message });
  }

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
    VALUES (?, ?, ?, 'whatsapp', 'outbound', ?, ?)
  `).run(id, tid, lead_id, message, created_by || null);

  const logged = await db.prepare('SELECT * FROM communications WHERE id = ?').get(id);
  res.status(201).json({ sent: true, logged });
});

module.exports = router;
