const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// The Leads List row's optional fields, in display order. 'field_*' join
// into the subtitle line (in sort_order, separated by " · "); 'badge_*'
// render in the trailing column. Only field_source, badge_stage, and
// badge_score default enabled -- matches the row's original fixed layout
// (source ?? phone fallback + stage chip + score badge) so turning this
// on for an existing tenant doesn't visually change anything until they
// actually customize it.
const DEFAULTS = [
  { field_key: 'field_phone',        enabled: false, sort_order: 0 },
  { field_key: 'field_email',        enabled: false, sort_order: 1 },
  { field_key: 'field_source',       enabled: true,  sort_order: 2 },
  { field_key: 'field_assigned_to',  enabled: false, sort_order: 3 },
  { field_key: 'field_created_date', enabled: false, sort_order: 4 },
  { field_key: 'badge_stage',        enabled: true,  sort_order: 5 },
  { field_key: 'badge_score',        enabled: true,  sort_order: 6 },
];

// Ensures a tenant has all 7 built-in field rows. Safe to call every
// time -- ON CONFLICT DO NOTHING makes it a no-op after the first run.
async function ensureSeeded(tid) {
  for (const def of DEFAULTS) {
    await db.prepare(`
      INSERT INTO lead_list_fields (id, tenant_id, field_key, enabled, sort_order)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT (tenant_id, field_key) DO NOTHING
    `).run(randomUUID(), tid, def.field_key, def.enabled, def.sort_order);
  }
}

// GET /lead-list-fields -- full config for this tenant, built-ins
// auto-seeded on first call. Sorted by sort_order for direct UI rendering.
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  await ensureSeeded(tid);
  const rows = await db.prepare('SELECT * FROM lead_list_fields WHERE tenant_id = ? ORDER BY sort_order ASC').all(tid);
  res.json(rows);
});

// PATCH /lead-list-fields/:field_key -- update one field's visibility.
router.patch('/:field_key', async (req, res) => {
  const tid = tenantId(req);
  const { field_key } = req.params;

  const existing = await db.prepare('SELECT id FROM lead_list_fields WHERE tenant_id = ? AND field_key = ?').get(tid, field_key);
  if (!existing) return res.status(404).json({ error: 'Field not found for this tenant' });

  const allowed = ['enabled', 'sort_order', 'style_json'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) {
      updates.push(field + ' = ?');
      values.push(field === 'style_json' ? JSON.stringify(req.body[field]) : req.body[field]);
    }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });

  updates.push('updated_at = now()');
  values.push(tid, field_key);
  await db.prepare('UPDATE lead_list_fields SET ' + updates.join(', ') + ' WHERE tenant_id = ? AND field_key = ?').run(...values);

  res.json(await db.prepare('SELECT * FROM lead_list_fields WHERE tenant_id = ? AND field_key = ?').get(tid, field_key));
});

// PUT /lead-list-fields/reorder  { order: ['field_phone', 'badge_stage', ...] }
// Bulk reorder in one call -- the array's position becomes sort_order.
router.put('/reorder', async (req, res) => {
  const tid = tenantId(req);
  const { order } = req.body;
  if (!Array.isArray(order) || order.length === 0) {
    return res.status(400).json({ error: 'order must be a non-empty array of field_key strings' });
  }

  for (let i = 0; i < order.length; i++) {
    await db.prepare('UPDATE lead_list_fields SET sort_order = ?, updated_at = now() WHERE tenant_id = ? AND field_key = ?').run(i, tid, order[i]);
  }

  const rows = await db.prepare('SELECT * FROM lead_list_fields WHERE tenant_id = ? ORDER BY sort_order ASC').all(tid);
  res.json(rows);
});

module.exports = router;
