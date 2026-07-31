const express = require('express');
const db = require('../db');
const { triageMessage } = require('../services/smartTriage');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// POST /triage/test  { lead_id, message } — try triage without sending
// anything, so a consultancy can see what the AI would do before turning
// on AUTO_TRIAGE_ENABLED.
router.post('/test', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, message } = req.body;
  if (!message) return res.status(400).json({ error: 'message is required' });

  const result = await triageMessage(tid, lead_id, message);
  res.json(result);
});

// GET /triage/status — is auto-triage on, and is AI configured for it
router.get('/status', (req, res) => {
  res.json({
    auto_triage_enabled: process.env.AUTO_TRIAGE_ENABLED === 'true',
    note: 'Set AUTO_TRIAGE_ENABLED=true in .env to let the app auto-reply to WhatsApp messages using your Knowledge Base.',
  });
});

module.exports = router;
