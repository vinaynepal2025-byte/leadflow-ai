const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { createNotification } = require('./notifications');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

const OUTCOMES = ['connected', 'no-answer', 'busy', 'wrong-number', 'voicemail', 'call-back-requested', 'switched-off', 'not-reachable', 'converted', 'not-interested'];

// GET /calls?lead_id=xxx
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  const rows = lead_id
    ? await db.prepare('SELECT * FROM call_logs WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC').all(tid, lead_id)
    : await db.prepare('SELECT * FROM call_logs WHERE tenant_id = ? ORDER BY created_at DESC LIMIT 100').all(tid);
  res.json(rows);
});

// POST /calls — log a call outcome; also mirrors into Communication Hub
// so Audit Center's unified timeline picks it up automatically.
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, duration_seconds, outcome, notes, called_by } = req.body;

  if (!lead_id || !outcome) return res.status(400).json({ error: 'lead_id and outcome are required' });
  if (!OUTCOMES.includes(outcome)) {
    return res.status(400).json({ error: `outcome must be one of: ${OUTCOMES.join(', ')}` });
  }
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO call_logs (id, tenant_id, lead_id, duration_seconds, outcome, notes, called_by)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, duration_seconds || null, outcome, notes || null, called_by || null);

  await db.prepare(`
    INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
    VALUES (?, ?, ?, 'call', 'outbound', ?, ?)
  `).run(randomUUID(), tid, lead_id, `Call outcome: ${outcome}${notes ? ` — ${notes}` : ''}`, called_by || null);

  if (outcome === 'no-answer' || outcome === 'busy') {
    await createNotification(tid, {
      title: `Missed connection with ${lead.full_name}`,
      body: `Call outcome: ${outcome}`,
      linkType: 'lead',
      linkId: lead_id,
    });
  }

  res.status(201).json(await db.prepare('SELECT * FROM call_logs WHERE id = ?').get(id));
});

module.exports = router;
