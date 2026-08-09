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

module.exports = router;
