const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const db = require('../db');

const router = express.Router();
const LOGO_DIR = path.join(__dirname, '..', 'uploads', 'logos');
if (!fs.existsSync(LOGO_DIR)) fs.mkdirSync(LOGO_DIR, { recursive: true });
const upload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => cb(null, LOGO_DIR),
    filename: (req, file, cb) => cb(null, `${tenantId(req)}-${file.originalname}`),
  }),
  limits: { fileSize: 2 * 1024 * 1024 },
});

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /settings — current tenant's configuration
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const tenant = await db.prepare('SELECT * FROM tenants WHERE id = ?').get(tid);
  if (!tenant) return res.status(404).json({ error: 'Tenant not found' });
  res.json(tenant);
});

// PATCH /settings — update branding/contact info
// Note: v1 covers name/logo/theme/contact — enough for a real white-label
// starting point (per-tenant branding). Custom domain routing and full
// theming (fonts, layout) are infrastructure-level and noted as separate,
// later work rather than half-built here.
router.patch('/', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM tenants WHERE id = ?').get(tid);
  if (!existing) return res.status(404).json({ error: 'Tenant not found' });

  const allowed = ['name', 'logo_url', 'theme_color', 'contact_email', 'contact_phone'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) {
      updates.push(`${field} = ?`);
      values.push(req.body[field]);
    }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });

  values.push(tid);
  await db.prepare(`UPDATE tenants SET ${updates.join(', ')} WHERE id = ?`).run(...values);
  res.json(await db.prepare('SELECT * FROM tenants WHERE id = ?').get(tid));
});

// POST /settings/logo  (multipart: file=<image>)
router.post('/logo', upload.single('file'), async (req, res) => {
  const tid = tenantId(req);
  if (!req.file) return res.status(400).json({ error: 'file is required (image)' });

  const logoUrl = `/settings/logo/${req.file.filename}`;
  await db.prepare('UPDATE tenants SET logo_url = ? WHERE id = ?').run(logoUrl, tid);
  res.status(201).json({ logo_url: logoUrl });
});

// GET /settings/logo/:filename — serves the uploaded logo image
router.get('/logo/:filename', async (req, res) => {
  const filePath = path.join(LOGO_DIR, req.params.filename);
  if (!fs.existsSync(filePath)) return res.status(404).json({ error: 'Logo not found' });
  res.sendFile(filePath);
});

module.exports = router;
