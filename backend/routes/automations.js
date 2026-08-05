const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

const VALID_TRIGGERS = ['lead.created', 'lead.stage_changed', 'document.rejected', 'offer.given'];
const VALID_ACTIONS = ['create_reminder', 'create_notification'];

// GET /automations
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const rows = await db.prepare('SELECT * FROM automation_rules WHERE tenant_id = ? ORDER BY created_at DESC').all(tid);
  res.json(rows.map((r) => ({ ...r, action_config: JSON.parse(r.action_config) })));
});

// POST /automations
// { name, trigger_event, condition_field?, condition_value?, action_type, action_config }
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { name, trigger_event, condition_field, condition_value, action_type, action_config } = req.body;

  if (!name || !trigger_event || !action_type || !action_config) {
    return res.status(400).json({ error: 'name, trigger_event, action_type, and action_config are required' });
  }
  if (!VALID_TRIGGERS.includes(trigger_event)) {
    return res.status(400).json({ error: `trigger_event must be one of: ${VALID_TRIGGERS.join(', ')}` });
  }
  if (!VALID_ACTIONS.includes(action_type)) {
    return res.status(400).json({ error: `action_type must be one of: ${VALID_ACTIONS.join(', ')}` });
  }

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO automation_rules (id, tenant_id, name, trigger_event, condition_field, condition_value, action_type, action_config)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, name, trigger_event, condition_field || null, condition_value || null, action_type, JSON.stringify(action_config));

  const created = await db.prepare('SELECT * FROM automation_rules WHERE id = ?').get(id);
  res.status(201).json({ ...created, action_config: JSON.parse(created.action_config) });
});

// PATCH /automations/:id  { enabled: false }
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM automation_rules WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Rule not found' });
  await db.prepare('UPDATE automation_rules SET enabled = ? WHERE tenant_id = ? AND id = ?')
    .run(req.body.enabled ? 1 : 0, tid, req.params.id);
  res.json({ ok: true });
});

module.exports = router;
