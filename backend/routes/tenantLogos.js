const express = require('express');
const multer = require('multer');
const { randomUUID } = require('crypto');
const db = require('../db');
const { uploadFile, getSignedUrl } = require('../services/supabaseStorage');
const { listTemplates, renderLogoTemplate } = require('../services/logoTemplates');

// sharp is loaded LAZILY -- same deliberate safety choice as
// routes/flyers.js: if sharp fails to load, only logo generation
// fails, the rest of the backend (including logo upload/list/delete
// above) keeps working.
let sharpModule = null;
let sharpLoadError = null;
function getSharp() {
  if (sharpModule) return sharpModule;
  if (sharpLoadError) throw sharpLoadError;
  try {
    sharpModule = require('sharp');
    return sharpModule;
  } catch (err) {
    sharpLoadError = err;
    throw err;
  }
}

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /tenant-logos — list with signed download URLs, most-recent first.
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const rows = await db.prepare('SELECT * FROM tenant_logos WHERE tenant_id = ? ORDER BY is_default DESC, created_at DESC').all(tid);
  const withUrls = await Promise.all(rows.map(async (r) => {
    try {
      return { ...r, image_url: await getSignedUrl(r.storage_path, 3600) };
    } catch (err) {
      return { ...r, image_url: null, url_error: err.message };
    }
  }));
  res.json(withUrls);
});

// POST /tenant-logos  (multipart: file, label?, is_default?)
router.post('/', upload.single('file'), async (req, res) => {
  const tid = tenantId(req);
  if (!req.file) return res.status(400).json({ error: 'file is required' });

  const id = randomUUID();
  const storagePath = `tenant-logos/${tid}/${id}-${req.file.originalname}`;

  try {
    await uploadFile(req.file.buffer, storagePath, req.file.mimetype);
  } catch (err) {
    return res.status(502).json({ error: `Upload failed: ${err.message}` });
  }

  const isDefault = req.body.is_default === 'true';
  if (isDefault) {
    await db.prepare('UPDATE tenant_logos SET is_default = false WHERE tenant_id = ?').run(tid);
  }

  await db.prepare(`
    INSERT INTO tenant_logos (id, tenant_id, label, storage_path, is_default)
    VALUES (?, ?, ?, ?, ?)
  `).run(id, tid, req.body.label || null, storagePath, isDefault);

  const created = await db.prepare('SELECT * FROM tenant_logos WHERE id = ?').get(id);
  const imageUrl = await getSignedUrl(storagePath, 3600);
  res.status(201).json({ ...created, image_url: imageUrl });
});

// PATCH /tenant-logos/:id  { label?, is_default? }
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM tenant_logos WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Logo not found' });

  if (req.body.is_default === true) {
    await db.prepare('UPDATE tenant_logos SET is_default = false WHERE tenant_id = ?').run(tid);
  }

  const allowed = ['label', 'is_default'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) { updates.push(field + ' = ?'); values.push(req.body[field]); }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });
  values.push(tid, req.params.id);
  await db.prepare('UPDATE tenant_logos SET ' + updates.join(', ') + ' WHERE tenant_id = ? AND id = ?').run(...values);

  res.json(await db.prepare('SELECT * FROM tenant_logos WHERE id = ?').get(req.params.id));
});

// DELETE /tenant-logos/:id
router.delete('/:id', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare('DELETE FROM tenant_logos WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Logo not found' });
  res.status(200).json({ deleted: true });
});

// GET /tenant-logos/templates -- Phase 1 (template/parametric) logo
// generator's available templates. Kept in this file rather than a
// separate route file since it's a thin sibling of the existing
// logo CRUD, not a distinct feature area.
router.get('/templates', (req, res) => {
  res.json({ templates: listTemplates() });
});

// POST /tenant-logos/generate  { template_id, fields }
// Renders a preview PNG (base64 data URI) immediately -- NOT saved.
// The Flutter side writes this to a temp file and calls the existing
// POST / (multipart upload) route to actually save it, so a
// generated logo goes through the exact same storage path as an
// uploaded one -- no separate save-a-generated-logo route needed.
router.post('/generate', async (req, res) => {
  const { template_id, fields } = req.body;
  if (!template_id) return res.status(400).json({ error: 'template_id is required' });
  try {
    const svg = renderLogoTemplate(template_id, fields || {});
    const png = await getSharp()(Buffer.from(svg)).png().toBuffer();
    res.json({ image_data_uri: `data:image/png;base64,${png.toString('base64')}` });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

module.exports = router;
