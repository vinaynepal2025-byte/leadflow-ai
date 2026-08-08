const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// The 10 built-in Lead Detail sections and their defaults. Phase 2 (custom
// buttons) will add rows with is_custom=true that aren't in this list —
// this DEFAULTS array only covers the fixed, built-in set.
const DEFAULTS = [
  { section_key: 'ai_insight',           default_label: 'AI Insight',              sort_order: 0 },
  { section_key: 'calling_cockpit',      default_label: 'Open Calling Cockpit',    sort_order: 1 },
  { section_key: 'whatsapp',             default_label: 'Send WhatsApp (free)',    sort_order: 2 },
  { section_key: 'documents',            default_label: 'Documents',               sort_order: 3 },
  { section_key: 'admissions_fees',      default_label: 'Admissions & Fees',       sort_order: 4 },
  { section_key: 'calls_voice_notes',    default_label: 'Calls & Voice Notes',     sort_order: 5 },
  { section_key: 'meetings',             default_label: 'Meetings & Campus Tours', sort_order: 6 },
  { section_key: 'visa_travel_student',  default_label: 'Visa, Travel & Student',  sort_order: 7 },
  { section_key: 'alumni',               default_label: 'Alumni Network',          sort_order: 8 },
  { section_key: 'consent_compliance',   default_label: 'Consent & Compliance',    sort_order: 9 },
];

// Ensures a tenant has all 10 built-in section rows. Safe to call every
// time — uses ON CONFLICT DO NOTHING so it's a no-op after the first run.
// This means a brand-new tenant gets sensible defaults automatically on
// their very first GET, no separate signup-time seeding step needed.
async function ensureSeeded(tid) {
  for (const def of DEFAULTS) {
    await db.prepare(`
      INSERT INTO lead_detail_sections (id, tenant_id, section_key, is_custom, enabled, sort_order, custom_label)
      VALUES (?, ?, ?, false, true, ?, NULL)
      ON CONFLICT (tenant_id, section_key) DO NOTHING
    `).run(randomUUID(), tid, def.section_key, def.sort_order);
  }
}

// GET /lead-detail-sections — full config for this tenant, built-ins
// auto-seeded on first call. Sorted by sort_order for direct UI rendering.
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  await ensureSeeded(tid);
  const rows = await db.prepare('SELECT * FROM lead_detail_sections WHERE tenant_id = ? ORDER BY sort_order ASC').all(tid);
  res.json(rows);
});

// PATCH /lead-detail-sections/:section_key — update one section's
// visibility, label, or style overrides. Works for both built-in and
// (later) custom sections since both live in the same table.
router.patch('/:section_key', async (req, res) => {
  const tid = tenantId(req);
  const { section_key } = req.params;

  const existing = await db.prepare('SELECT id FROM lead_detail_sections WHERE tenant_id = ? AND section_key = ?').get(tid, section_key);
  if (!existing) return res.status(404).json({ error: 'Section not found for this tenant' });

  const allowed = ['enabled', 'sort_order', 'custom_label', 'icon_override', 'color_override', 'size_override', 'shape_override'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) { updates.push(field + ' = ?'); values.push(req.body[field]); }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });

  updates.push('updated_at = now()');
  values.push(tid, section_key);
  await db.prepare('UPDATE lead_detail_sections SET ' + updates.join(', ') + ' WHERE tenant_id = ? AND section_key = ?').run(...values);

  res.json(await db.prepare('SELECT * FROM lead_detail_sections WHERE tenant_id = ? AND section_key = ?').get(tid, section_key));
});

// PUT /lead-detail-sections/reorder  { order: ['documents', 'whatsapp', ...] }
// Bulk reorder in one call — the array's position becomes sort_order.
// Built for a drag-reorder UI that shouldn't fire N separate PATCH calls.
router.put('/reorder', async (req, res) => {
  const tid = tenantId(req);
  const { order } = req.body;
  if (!Array.isArray(order) || order.length === 0) {
    return res.status(400).json({ error: 'order must be a non-empty array of section_key strings' });
  }

  for (let i = 0; i < order.length; i++) {
    await db.prepare('UPDATE lead_detail_sections SET sort_order = ?, updated_at = now() WHERE tenant_id = ? AND section_key = ?').run(i, tid, order[i]);
  }

  const rows = await db.prepare('SELECT * FROM lead_detail_sections WHERE tenant_id = ? ORDER BY sort_order ASC').all(tid);
  res.json(rows);
});

// DELETE /lead-detail-sections/:section_key — only for custom (Phase 2)
// sections. Built-in sections can be hidden (enabled=false) but not
// removed, since the app's Dart code expects all 10 keys to exist.
router.delete('/:section_key', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT is_custom FROM lead_detail_sections WHERE tenant_id = ? AND section_key = ?').get(tid, req.params.section_key);
  if (!existing) return res.status(404).json({ error: 'Section not found for this tenant' });
  if (!existing.is_custom) {
    return res.status(400).json({ error: 'Built-in sections cannot be deleted — set enabled:false to hide instead' });
  }
  await db.prepare('DELETE FROM lead_detail_sections WHERE tenant_id = ? AND section_key = ?').run(tid, req.params.section_key);
  res.status(200).json({ deleted: true });
});

module.exports = router;
