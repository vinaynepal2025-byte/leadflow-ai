const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { getSignedUrl } = require('../services/supabaseStorage');

const router = express.Router();

const LOGO_ROLE_COLUMNS = [
  'primary_logo_id',
  'secondary_logo_id',
  'mono_logo_id',
  'dark_bg_logo_id',
  'light_bg_logo_id',
  'icon_mark_logo_id',
];

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// Resolves every *_logo_id column to its signed image URL in one pass, so
// the client never has to make a separate round trip per role -- a Brand
// Kit is meant to render as one glanceable screen.
async function attachLogoUrls(kit) {
  if (!kit) return kit;
  const ids = LOGO_ROLE_COLUMNS.map((c) => kit[c]).filter(Boolean);
  if (ids.length === 0) return { ...kit };

  const placeholders = ids.map(() => '?').join(', ');
  const logos = await db
    .prepare(`SELECT id, label, storage_path FROM tenant_logos WHERE id IN (${placeholders})`)
    .all(...ids);
  const byId = new Map(logos.map((l) => [l.id, l]));

  const withUrls = { ...kit };
  for (const col of LOGO_ROLE_COLUMNS) {
    const id = kit[col];
    if (!id) continue;
    const logo = byId.get(id);
    if (!logo) continue;
    try {
      withUrls[`${col}_url`] = await getSignedUrl(logo.storage_path, 3600);
    } catch (err) {
      withUrls[`${col}_url`] = null;
    }
  }
  return withUrls;
}

// GET /brand-kit — the tenant's brand kit, or null if none has been
// created yet (the client shows an empty/setup state in that case).
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const kit = await db.prepare('SELECT * FROM tenant_brand_kits WHERE tenant_id = ? ORDER BY created_at ASC LIMIT 1').get(tid);
  res.json(await attachLogoUrls(kit) ?? null);
});

// PUT /brand-kit — upserts the tenant's one brand kit (creates it on
// first call). Every field is optional so the client can save one role
// assignment at a time (e.g. "set this logo as Primary") without
// resending the whole kit.
router.put('/', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM tenant_brand_kits WHERE tenant_id = ? ORDER BY created_at ASC LIMIT 1').get(tid);

  const allowed = [...LOGO_ROLE_COLUMNS, 'name', 'palette', 'font_primary', 'font_secondary'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) {
      updates.push(field + ' = ?');
      values.push(field === 'palette' ? JSON.stringify(req.body[field]) : req.body[field]);
    }
  }

  if (existing) {
    if (updates.length > 0) {
      updates.push('updated_at = now()');
      values.push(tid, existing.id);
      await db.prepare('UPDATE tenant_brand_kits SET ' + updates.join(', ') + ' WHERE tenant_id = ? AND id = ?').run(...values);
    }
    res.json(await attachLogoUrls(await db.prepare('SELECT * FROM tenant_brand_kits WHERE id = ?').get(existing.id)));
    return;
  }

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO tenant_brand_kits (id, tenant_id, name, primary_logo_id, secondary_logo_id, mono_logo_id, dark_bg_logo_id, light_bg_logo_id, icon_mark_logo_id, palette, font_primary, font_secondary)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    id, tid, req.body.name || 'Brand Kit',
    req.body.primary_logo_id || null, req.body.secondary_logo_id || null, req.body.mono_logo_id || null,
    req.body.dark_bg_logo_id || null, req.body.light_bg_logo_id || null, req.body.icon_mark_logo_id || null,
    JSON.stringify(req.body.palette || []), req.body.font_primary || null, req.body.font_secondary || null,
  );

  res.status(201).json(await attachLogoUrls(await db.prepare('SELECT * FROM tenant_brand_kits WHERE id = ?').get(id)));
});

module.exports = router;
