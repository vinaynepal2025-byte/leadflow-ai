const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { sendEmail } = require('../services/email');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// POST /email/send  { lead_id, subject, message, created_by }
router.post('/send', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, subject, message, created_by } = req.body;

  if (!lead_id || !subject || !message) {
    return res.status(400).json({ error: 'lead_id, subject, and message are required' });
  }
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });
  if (!lead.email) return res.status(400).json({ error: 'This lead has no email address on file' });

  const tenant = await db.prepare('SELECT * FROM tenants WHERE id = ?').get(tid);

  try {
    await sendEmail(lead.email, subject, message, tenant);
  } catch (err) {
    return res.status(502).json({ error: err.message });
  }

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
    VALUES (?, ?, ?, 'email', 'outbound', ?, ?)
  `).run(id, tid, lead_id, `Subject: ${subject}\n\n${message}`, created_by || null);

  res.status(201).json({ sent: true, logged: await db.prepare('SELECT * FROM communications WHERE id = ?').get(id) });
});

module.exports = router;
