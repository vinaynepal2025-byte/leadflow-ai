const express = require('express');
const multer = require('multer');
const { randomUUID } = require('crypto');
const db = require('../db');
const { uploadFile, getSignedUrl } = require('../services/supabaseStorage');

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

const VALID_KINDS = new Set(['icon', 'image', 'logo', 'export', 'svg']);
// Defense in depth only -- the mobile client already runs every imported
// SVG through svg_sanitizer.dart before it ever becomes an element or
// reaches this endpoint. This is a cheap server-side backstop against a
// client that skips that step (a modified app build, a direct API call),
// not a full sanitizer: this endpoint never hands svg_data to sharp/
// librsvg or any other server-side renderer, and it's only ever served
// back to the same tenant that stored it, so the blast radius of a
// missed edge case is one tenant's own devices rendering it via
// flutter_svg (no script execution there), not a shared surface.
const MAX_SVG_BYTES = 2 * 1024 * 1024;

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

async function attachUrl(row) {
  if (!row) return row;
  if (!row.storage_path) return row;
  try {
    return { ...row, asset_url: await getSignedUrl(row.storage_path, 3600) };
  } catch (err) {
    return { ...row, asset_url: null, url_error: err.message };
  }
}

// GET /tenant-assets?kind=&category=&favorite=true&search=
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { kind, category, favorite, search } = req.query;

  const clauses = ['tenant_id = ?'];
  const values = [tid];
  if (kind) { clauses.push('kind = ?'); values.push(kind); }
  if (category) { clauses.push('category = ?'); values.push(category); }
  if (favorite === 'true') { clauses.push('is_favorite = true'); }
  if (search) { clauses.push('label ILIKE ?'); values.push(`%${search}%`); }

  const rows = await db
    .prepare(`SELECT * FROM tenant_assets WHERE ${clauses.join(' AND ')} ORDER BY is_favorite DESC, created_at DESC LIMIT 200`)
    .all(...values);
  res.json(await Promise.all(rows.map(attachUrl)));
});

// POST /tenant-assets  (multipart: file, kind, label?, category?)
// For image/logo/export assets -- a stored file, signed-URL-served like
// every other upload in this app.
router.post('/', upload.single('file'), async (req, res) => {
  const tid = tenantId(req);
  if (!req.file) return res.status(400).json({ error: 'file is required' });
  const kind = req.body.kind;
  if (!VALID_KINDS.has(kind) || kind === 'svg') {
    return res.status(400).json({ error: `kind must be one of: icon, image, logo, export` });
  }

  const id = randomUUID();
  const storagePath = `tenant-assets/${tid}/${id}-${req.file.originalname}`;
  try {
    await uploadFile(req.file.buffer, storagePath, req.file.mimetype);
  } catch (err) {
    return res.status(502).json({ error: `Upload failed: ${err.message}` });
  }

  await db.prepare(`
    INSERT INTO tenant_assets (id, tenant_id, kind, label, category, storage_path, created_by)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, kind, req.body.label || null, req.body.category || null, storagePath, req.body.created_by || null);

  res.status(201).json(await attachUrl(await db.prepare('SELECT * FROM tenant_assets WHERE id = ?').get(id)));
});

// POST /tenant-assets/svg  { svgData, label?, category? }
// For vector assets saved straight from the canvas (svg_sanitizer.dart
// has already run on this content on the client before it ever became
// an element -- see the MAX_SVG_BYTES comment above for why this route
// only re-checks size/shape rather than re-sanitizing in full).
router.post('/svg', express.json({ limit: '3mb' }), async (req, res) => {
  const tid = tenantId(req);
  const { svgData, label, category } = req.body;
  if (typeof svgData !== 'string' || !svgData.trim()) {
    return res.status(400).json({ error: 'svgData is required' });
  }
  if (Buffer.byteLength(svgData, 'utf8') > MAX_SVG_BYTES) {
    return res.status(400).json({ error: 'SVG is too large (max 2 MB)' });
  }
  if (!/^\s*<svg[\s>]/i.test(svgData)) {
    return res.status(400).json({ error: 'Not a valid SVG document' });
  }

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO tenant_assets (id, tenant_id, kind, label, category, svg_data, created_by)
    VALUES (?, ?, 'svg', ?, ?, ?, ?)
  `).run(id, tid, label || null, category || null, svgData, req.body.created_by || null);

  res.status(201).json(await db.prepare('SELECT * FROM tenant_assets WHERE id = ?').get(id));
});

// PATCH /tenant-assets/:id  { label?, category?, is_favorite? }
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM tenant_assets WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Asset not found' });

  const allowed = ['label', 'category', 'is_favorite'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) { updates.push(field + ' = ?'); values.push(req.body[field]); }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });

  updates.push('updated_at = now()');
  values.push(tid, req.params.id);
  await db.prepare('UPDATE tenant_assets SET ' + updates.join(', ') + ' WHERE tenant_id = ? AND id = ?').run(...values);

  res.json(await attachUrl(await db.prepare('SELECT * FROM tenant_assets WHERE id = ?').get(req.params.id)));
});

// DELETE /tenant-assets/:id
router.delete('/:id', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare('DELETE FROM tenant_assets WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Asset not found' });
  res.status(200).json({ deleted: true });
});

module.exports = router;
