const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// The Dashboard's built-in widgets and their defaults, in display order.
// Unlike lead_detail_sections there's no custom/Phase-2 concept here --
// the Dashboard's widgets are all fixed app functionality (metrics, the
// pipeline chart, the Work Queue shortcut), so this route only ever
// covers show/hide + reorder + an optional accent-colour override, never
// creating new arbitrary sections.
const DEFAULTS = [
  { section_key: 'work_queue',              sort_order: 0 },
  { section_key: 'metric_total_leads',      sort_order: 1 },
  { section_key: 'metric_conversion',       sort_order: 2 },
  { section_key: 'metric_pending_followups', sort_order: 3 },
  { section_key: 'metric_overdue',          sort_order: 4 },
  { section_key: 'pipeline_breakdown',      sort_order: 5 },
];

// Ensures a tenant has all 6 built-in section rows. Safe to call every
// time -- ON CONFLICT DO NOTHING makes it a no-op after the first run, so
// a brand-new tenant gets sensible defaults on their very first GET.
async function ensureSeeded(tid) {
  for (const def of DEFAULTS) {
    await db.prepare(`
      INSERT INTO dashboard_sections (id, tenant_id, section_key, enabled, sort_order)
      VALUES (?, ?, ?, true, ?)
      ON CONFLICT (tenant_id, section_key) DO NOTHING
    `).run(randomUUID(), tid, def.section_key, def.sort_order);
  }
}

// GET /dashboard-sections -- full config for this tenant, built-ins
// auto-seeded on first call. Sorted by sort_order for direct UI rendering.
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  await ensureSeeded(tid);
  const rows = await db.prepare('SELECT * FROM dashboard_sections WHERE tenant_id = ? ORDER BY sort_order ASC').all(tid);
  res.json(rows);
});

// PATCH /dashboard-sections/:section_key -- update one section's
// visibility or accent colour.
router.patch('/:section_key', async (req, res) => {
  const tid = tenantId(req);
  const { section_key } = req.params;

  const existing = await db.prepare('SELECT id FROM dashboard_sections WHERE tenant_id = ? AND section_key = ?').get(tid, section_key);
  if (!existing) return res.status(404).json({ error: 'Section not found for this tenant' });

  const allowed = ['enabled', 'sort_order', 'color_override'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) { updates.push(field + ' = ?'); values.push(req.body[field]); }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });

  updates.push('updated_at = now()');
  values.push(tid, section_key);
  await db.prepare('UPDATE dashboard_sections SET ' + updates.join(', ') + ' WHERE tenant_id = ? AND section_key = ?').run(...values);

  res.json(await db.prepare('SELECT * FROM dashboard_sections WHERE tenant_id = ? AND section_key = ?').get(tid, section_key));
});

// PUT /dashboard-sections/reorder  { order: ['work_queue', 'metric_total_leads', ...] }
// Bulk reorder in one call -- the array's position becomes sort_order.
router.put('/reorder', async (req, res) => {
  const tid = tenantId(req);
  const { order } = req.body;
  if (!Array.isArray(order) || order.length === 0) {
    return res.status(400).json({ error: 'order must be a non-empty array of section_key strings' });
  }

  for (let i = 0; i < order.length; i++) {
    await db.prepare('UPDATE dashboard_sections SET sort_order = ?, updated_at = now() WHERE tenant_id = ? AND section_key = ?').run(i, tid, order[i]);
  }

  const rows = await db.prepare('SELECT * FROM dashboard_sections WHERE tenant_id = ? ORDER BY sort_order ASC').all(tid);
  res.json(rows);
});

module.exports = router;
