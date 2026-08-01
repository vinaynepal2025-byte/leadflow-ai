const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /communications?lead_id=xxx — history for one lead (or all, for a tenant-wide feed)
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  let rows;
  if (lead_id) {
    rows = await db.prepare(
      'SELECT * FROM communications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC'
    ).all(tid, lead_id);
  } else {
    rows = await db.prepare(
      'SELECT * FROM communications WHERE tenant_id = ? ORDER BY created_at DESC LIMIT 100'
    ).all(tid);
  }
  res.json(rows);
});

// POST /communications — log a new interaction (manual log: call summary, note, etc.)
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, channel, direction, body, created_by } = req.body;

  if (!lead_id || !channel || !direction) {
    return res.status(400).json({ error: 'lead_id, channel, and direction are required' });
  }
  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found for this tenant' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, channel, direction, body || null, created_by || null);

  const created = await db.prepare('SELECT * FROM communications WHERE id = ?').get(id);
  res.status(201).json(created);
});

module.exports = router;
