const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// Built-in share-targets. custom_package_or_scheme is the Android package
// name (for share_plus's package-targeted sharing where supported) or a
// URL-scheme fallback — the Flutter side decides how to use it per-platform.
const DEFAULTS = [
  { target_key: 'whatsapp',   default_label: 'WhatsApp',   sort_order: 0, scheme: 'whatsapp' },
  { target_key: 'instagram',  default_label: 'Instagram',  sort_order: 1, scheme: 'instagram' },
  { target_key: 'facebook',   default_label: 'Facebook',   sort_order: 2, scheme: 'facebook' },
  { target_key: 'telegram',   default_label: 'Telegram',   sort_order: 3, scheme: 'telegram' },
  { target_key: 'email',      default_label: 'Email',      sort_order: 4, scheme: 'email' },
  { target_key: 'more',       default_label: 'More apps...', sort_order: 5, scheme: 'system_share_sheet' },
];

async function ensureSeeded(tid) {
  for (const def of DEFAULTS) {
    await db.prepare(`
      INSERT INTO share_targets (id, tenant_id, target_key, is_custom, enabled, sort_order, custom_package_or_scheme)
      VALUES (?, ?, ?, false, true, ?, ?)
      ON CONFLICT (tenant_id, target_key) DO NOTHING
    `).run(randomUUID(), tid, def.target_key, def.sort_order, def.scheme);
  }
}

// GET /share-targets
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  await ensureSeeded(tid);
  const rows = await db.prepare('SELECT * FROM share_targets WHERE tenant_id = ? ORDER BY sort_order ASC').all(tid);
  res.json(rows);
});

// POST /share-targets — add a custom share-target (e.g. a specific
// LinkedIn company page, a regional platform not in the defaults).
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { custom_label, custom_package_or_scheme, icon_override, color_override } = req.body;
  if (!custom_label) return res.status(400).json({ error: 'custom_label is required' });

  const baseKey = 'custom_' + custom_label.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40);
  let key = baseKey || 'custom_target';
  let suffix = 1;
  while (await db.prepare('SELECT id FROM share_targets WHERE tenant_id = ? AND target_key = ?').get(tid, key)) {
    suffix += 1;
    key = baseKey + '_' + suffix;
  }

  const maxOrder = await db.prepare('SELECT COALESCE(MAX(sort_order), -1) AS m FROM share_targets WHERE tenant_id = ?').get(tid);
  const id = randomUUID();
  await db.prepare(`
    INSERT INTO share_targets (id, tenant_id, target_key, is_custom, enabled, sort_order, custom_label, custom_package_or_scheme, icon_override, color_override)
    VALUES (?, ?, ?, true, true, ?, ?, ?, ?, ?)
  `).run(id, tid, key, maxOrder.m + 1, custom_label, custom_package_or_scheme || null, icon_override || null, color_override || null);

  res.status(201).json(await db.prepare('SELECT * FROM share_targets WHERE id = ?').get(id));
});

// PATCH /share-targets/:target_key
router.patch('/:target_key', async (req, res) => {
  const tid = tenantId(req);
  const { target_key } = req.params;
  const existing = await db.prepare('SELECT id FROM share_targets WHERE tenant_id = ? AND target_key = ?').get(tid, target_key);
  if (!existing) return res.status(404).json({ error: 'Share target not found for this tenant' });

  const allowed = ['enabled', 'sort_order', 'custom_label', 'icon_override', 'color_override', 'custom_package_or_scheme'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) { updates.push(field + ' = ?'); values.push(req.body[field]); }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });

  updates.push('updated_at = now()');
  values.push(tid, target_key);
  await db.prepare('UPDATE share_targets SET ' + updates.join(', ') + ' WHERE tenant_id = ? AND target_key = ?').run(...values);

  res.json(await db.prepare('SELECT * FROM share_targets WHERE tenant_id = ? AND target_key = ?').get(tid, target_key));
});

// PUT /share-targets/reorder  { order: [target_key, ...] }
router.put('/reorder', async (req, res) => {
  const tid = tenantId(req);
  const { order } = req.body;
  if (!Array.isArray(order) || order.length === 0) {
    return res.status(400).json({ error: 'order must be a non-empty array of target_key strings' });
  }
  for (let i = 0; i < order.length; i++) {
    await db.prepare('UPDATE share_targets SET sort_order = ?, updated_at = now() WHERE tenant_id = ? AND target_key = ?').run(i, tid, order[i]);
  }
  res.json(await db.prepare('SELECT * FROM share_targets WHERE tenant_id = ? ORDER BY sort_order ASC').all(tid));
});

// DELETE /share-targets/:target_key — custom targets only.
router.delete('/:target_key', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT is_custom FROM share_targets WHERE tenant_id = ? AND target_key = ?').get(tid, req.params.target_key);
  if (!existing) return res.status(404).json({ error: 'Share target not found' });
  if (!existing.is_custom) {
    return res.status(400).json({ error: 'Built-in share targets cannot be deleted — set enabled:false to hide instead' });
  }
  await db.prepare('DELETE FROM share_targets WHERE tenant_id = ? AND target_key = ?').run(tid, req.params.target_key);
  res.status(200).json({ deleted: true });
});

module.exports = router;
