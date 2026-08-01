const express = require('express');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /inbox?channel=whatsapp&limit=50
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { channel, limit } = req.query;
  const max = Math.min(parseInt(limit) || 50, 200);

  let query = `
    SELECT c.id, c.lead_id, c.channel, c.direction, c.body, c.created_by, c.created_at,
           l.full_name AS lead_name, l.phone AS lead_phone, l.stage
    FROM communications c JOIN leads l ON l.id = c.lead_id
    WHERE c.tenant_id = ?
  `;
  const params = [tid];
  if (channel) {
    query += ' AND c.channel = ?';
    params.push(channel);
  }
  query += ' ORDER BY c.created_at DESC LIMIT ?';
  params.push(max);

  res.json(await db.prepare(query).all(...params));
});

// GET /inbox/unreplied — leads whose last message was inbound and we
// haven't responded yet. The actual queue to clear first.
router.get('/unreplied', async (req, res) => {
  const tid = tenantId(req);

  const leadIds = await db.prepare('SELECT DISTINCT lead_id FROM communications WHERE tenant_id = ?').all(tid).map((r) => r.lead_id);
  const unreplied = [];

  for (const leadId of leadIds) {
    // rowid as tiebreaker: SQLite's datetime('now') has second precision,
    // so two messages logged within the same second would otherwise sort
    // arbitrarily — rowid guarantees "most recently inserted" wins.
    const last = await db.prepare(
      'SELECT * FROM communications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 1'
    ).get(tid, leadId);
    if (last && last.direction === 'inbound') {
      const lead = await db.prepare('SELECT full_name, phone, stage FROM leads WHERE id = ?').get(leadId);
      unreplied.push({ ...last, lead_name: lead?.full_name, lead_phone: lead?.phone, stage: lead?.stage });
    }
  }

  unreplied.sort((a, b) => (a.created_at < b.created_at ? -1 : 1));
  res.json(unreplied);
});

// GET /inbox/thread/:leadId — full cross-channel conversation with one lead
router.get('/thread/:leadId', async (req, res) => {
  const tid = tenantId(req);
  const rows = await db.prepare(
    'SELECT * FROM communications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at ASC'
  ).all(tid, req.params.leadId);
  res.json(rows);
});

module.exports = router;
