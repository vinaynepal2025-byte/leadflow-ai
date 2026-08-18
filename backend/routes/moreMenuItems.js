const express = require('express');
const multer = require('multer');
const { randomUUID } = require('crypto');
const db = require('../db');
const { uploadFile, getSignedUrl } = require('../services/supabaseStorage');

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// The 17 built-in More-menu items and their defaults. Direct answer to
// Vinay's "har smallest visible section par control chahiye" -- same
// proven pattern as lead_detail_sections.js / shareTargets.js (already
// shipped and working elsewhere in this app), applied here so the More
// menu's own tiles become genuinely per-item controllable: enable/
// disable, reorder, rename, re-icon, re-colour.
const DEFAULTS = [
  { item_key: 'flyer_studio',        default_label: 'Flyer Studio',           sort_order: 0 },
  { item_key: 'parent_crm',          default_label: 'Parent CRM',             sort_order: 1 },
  { item_key: 'team',                default_label: 'Team',                   sort_order: 2 },
  { item_key: 'colleges',            default_label: 'Colleges & Universities',sort_order: 3 },
  { item_key: 'calendar',            default_label: 'Calendar',               sort_order: 4 },
  { item_key: 'performance',         default_label: 'Performance',            sort_order: 5 },
  { item_key: 'audit_timeline',      default_label: 'Audit Timeline',         sort_order: 6 },
  { item_key: 'knowledge_base',      default_label: 'Knowledge Base',         sort_order: 7 },
  { item_key: 'automation_hub',      default_label: 'Automation Hub',         sort_order: 8 },
  { item_key: 'insights_records',    default_label: 'Insights & Records',     sort_order: 9 },
  { item_key: 'smart_triage',        default_label: 'Smart Triage',           sort_order: 10 },
  { item_key: 'lead_scoring',        default_label: 'Lead Scoring Rules',     sort_order: 11 },
  { item_key: 'lead_capture_forms',  default_label: 'Lead Capture Forms',     sort_order: 12 },
  { item_key: 'social_media_links',  default_label: 'Social Media Links',     sort_order: 13 },
  { item_key: 'pipeline_builder',    default_label: 'Pipeline Builder',       sort_order: 14 },
  { item_key: 'custom_fields',       default_label: 'Custom Fields',          sort_order: 15 },
  { item_key: 'settings',            default_label: 'Settings',               sort_order: 16 },
];

// Ensures a tenant has all 17 built-in item rows. Safe to call every
// time -- ON CONFLICT DO NOTHING makes it a no-op after the first run.
async function ensureSeeded(tid) {
  for (const def of DEFAULTS) {
    await db.prepare(`
      INSERT INTO more_menu_items (id, tenant_id, item_key, is_custom, enabled, sort_order, custom_label)
      VALUES (?, ?, ?, false, true, ?, NULL)
      ON CONFLICT (tenant_id, item_key) DO NOTHING
    `).run(randomUUID(), tid, def.item_key, def.sort_order);
  }
}

// Resolves icon_image_path to a signed URL -- same pattern as
// flyerProjects.js's attachUrls, one signed-URL call per row that
// actually has an uploaded icon (most rows have none, so this is cheap
// in practice).
async function attachIconUrl(row) {
  if (!row || !row.icon_image_path) return row;
  try {
    return { ...row, icon_image_url: await getSignedUrl(row.icon_image_path, 3600) };
  } catch (err) {
    return { ...row, icon_image_url: null };
  }
}

// GET /more-menu-items -- full config for this tenant, built-ins
// auto-seeded on first call. Sorted by sort_order for direct UI rendering.
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  await ensureSeeded(tid);
  const rows = await db.prepare('SELECT * FROM more_menu_items WHERE tenant_id = ? ORDER BY sort_order ASC').all(tid);
  res.json(await Promise.all(rows.map(attachIconUrl)));
});

// POST /more-menu-items/:item_key/icon-image  (multipart: file=<image>)
// Uploads a custom icon image, replacing the built-in Material glyph on
// this one tile -- "icon upload ka bhi option do".
router.post('/:item_key/icon-image', upload.single('file'), async (req, res) => {
  const tid = tenantId(req);
  const { item_key } = req.params;
  const existing = await db.prepare('SELECT id FROM more_menu_items WHERE tenant_id = ? AND item_key = ?').get(tid, item_key);
  if (!existing) return res.status(404).json({ error: 'Item not found for this tenant' });
  if (!req.file) return res.status(400).json({ error: 'file is required' });

  const storagePath = `tile-icons/${tid}/${item_key}-${randomUUID()}-${req.file.originalname}`;
  try {
    await uploadFile(req.file.buffer, storagePath, req.file.mimetype);
  } catch (err) {
    return res.status(502).json({ error: `Upload failed: ${err.message}` });
  }

  await db.prepare('UPDATE more_menu_items SET icon_image_path = ?, updated_at = now() WHERE tenant_id = ? AND item_key = ?')
    .run(storagePath, tid, item_key);

  res.json(await attachIconUrl(await db.prepare('SELECT * FROM more_menu_items WHERE tenant_id = ? AND item_key = ?').get(tid, item_key)));
});

// POST /more-menu-items -- create a custom item (opens a URL). Only
// custom items can be created this way; the 17 built-ins are seeded
// automatically and never created through this route.
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { custom_label, custom_action_value, icon_override, color_override, gradient_override, style_variant } = req.body;

  if (!custom_label || !custom_action_value) {
    return res.status(400).json({ error: 'custom_label and custom_action_value are required' });
  }
  if (!/^https?:\/\//i.test(custom_action_value)) {
    return res.status(400).json({ error: 'custom_action_value must start with http:// or https://' });
  }

  const baseKey = 'custom_' + custom_label.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40);
  let key = baseKey || 'custom_item';
  let suffix = 1;
  while (await db.prepare('SELECT id FROM more_menu_items WHERE tenant_id = ? AND item_key = ?').get(tid, key)) {
    suffix += 1;
    key = baseKey + '_' + suffix;
  }

  const maxOrder = await db.prepare('SELECT COALESCE(MAX(sort_order), -1) AS m FROM more_menu_items WHERE tenant_id = ?').get(tid);
  const id = randomUUID();
  await db.prepare(`
    INSERT INTO more_menu_items
      (id, tenant_id, item_key, is_custom, enabled, sort_order, custom_label, icon_override, color_override, gradient_override, style_variant, custom_action_type, custom_action_value)
    VALUES (?, ?, ?, true, true, ?, ?, ?, ?, ?, ?, 'url', ?)
  `).run(id, tid, key, maxOrder.m + 1, custom_label, icon_override || null, color_override || null, gradient_override || null, style_variant || 'flat', custom_action_value);

  res.status(201).json(await db.prepare('SELECT * FROM more_menu_items WHERE id = ?').get(id));
});

// PATCH /more-menu-items/:item_key -- update visibility, label, or
// style overrides. Works for both built-in and custom items.
router.patch('/:item_key', async (req, res) => {
  const tid = tenantId(req);
  const { item_key } = req.params;

  const existing = await db.prepare('SELECT id FROM more_menu_items WHERE tenant_id = ? AND item_key = ?').get(tid, item_key);
  if (!existing) return res.status(404).json({ error: 'Item not found for this tenant' });

  const allowed = ['enabled', 'sort_order', 'custom_label', 'icon_override', 'color_override', 'gradient_override', 'style_variant', 'style_json'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) {
      updates.push(field + ' = ?');
      values.push(field === 'style_json' ? JSON.stringify(req.body[field]) : req.body[field]);
    }
  }
  // icon_image_path is handled separately from the generic allow-list --
  // it's a storage path, and accepting an arbitrary client-supplied one
  // here would let a tenant point their tile at any object in the shared
  // bucket (including another tenant's private files) just by knowing
  // its path. The only legitimate way to SET it is the dedicated
  // POST /:item_key/icon-image upload route below, which generates the
  // path itself; PATCH only ever accepts explicit null, to remove a
  // previously uploaded icon and fall back to icon_override again.
  if (req.body.icon_image_path === null) {
    updates.push('icon_image_path = ?');
    values.push(null);
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });

  updates.push('updated_at = now()');
  values.push(tid, item_key);
  await db.prepare('UPDATE more_menu_items SET ' + updates.join(', ') + ' WHERE tenant_id = ? AND item_key = ?').run(...values);

  res.json(await attachIconUrl(await db.prepare('SELECT * FROM more_menu_items WHERE tenant_id = ? AND item_key = ?').get(tid, item_key)));
});

// PUT /more-menu-items/reorder  { order: ['flyer_studio', 'team', ...] }
router.put('/reorder', async (req, res) => {
  const tid = tenantId(req);
  const { order } = req.body;
  if (!Array.isArray(order) || order.length === 0) {
    return res.status(400).json({ error: 'order must be a non-empty array of item_key strings' });
  }
  for (let i = 0; i < order.length; i++) {
    await db.prepare('UPDATE more_menu_items SET sort_order = ?, updated_at = now() WHERE tenant_id = ? AND item_key = ?').run(i, tid, order[i]);
  }
  const rows = await db.prepare('SELECT * FROM more_menu_items WHERE tenant_id = ? ORDER BY sort_order ASC').all(tid);
  res.json(rows);
});

// DELETE /more-menu-items/:item_key -- custom items only. Built-ins can
// be hidden (enabled=false) but not removed, since the app's Dart code
// expects all 17 built-in keys to exist.
router.delete('/:item_key', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT is_custom FROM more_menu_items WHERE tenant_id = ? AND item_key = ?').get(tid, req.params.item_key);
  if (!existing) return res.status(404).json({ error: 'Item not found' });
  if (!existing.is_custom) {
    return res.status(400).json({ error: 'Built-in items cannot be deleted -- set enabled:false to hide instead' });
  }
  await db.prepare('DELETE FROM more_menu_items WHERE tenant_id = ? AND item_key = ?').run(tid, req.params.item_key);
  res.status(200).json({ deleted: true });
});

module.exports = router;
