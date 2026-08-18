const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const db = require('../db');
const { encrypt } = require('../services/crypto');

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

// Strips the encrypted API key blob out of a tenant row before it's ever
// sent back to a client -- ciphertext is useless without MASTER_KEY, but
// there's no reason to expose it at all. Replaced with a plain boolean so
// the app can show "Advanced email: configured" without seeing the secret.
function withoutSecrets(tenant) {
  if (!tenant) return tenant;
  const { own_brevo_api_key_encrypted, ...rest } = tenant;
  return { ...rest, has_own_email_provider: !!own_brevo_api_key_encrypted };
}

// GET /settings — current tenant's configuration
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const tenant = await db.prepare('SELECT * FROM tenants WHERE id = ?').get(tid);
  if (!tenant) return res.status(404).json({ error: 'Tenant not found' });
  res.json(withoutSecrets(tenant));
});

// PATCH /settings — update branding/contact info
// Note: v1 covers name/logo/theme/contact/reply-to — enough for a real
// white-label starting point (per-tenant branding). Custom domain routing
// and full theming (fonts, layout) are infrastructure-level and noted as
// separate, later work rather than half-built here.
router.patch('/', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM tenants WHERE id = ?').get(tid);
  if (!existing) return res.status(404).json({ error: 'Tenant not found' });

  // automation_mode: Leads Ecosystem Phase 6 (MANUAL/AUTO toggle). Kept
  // in this same generic allowed-fields loop as everything else, but
  // validated separately since it's the one field here with only two
  // legal values -- see services/agentScheduler.js for what 'auto'
  // actually turns on.
  if (req.body.automation_mode !== undefined && !['manual', 'auto'].includes(req.body.automation_mode)) {
    return res.status(400).json({ error: "automation_mode must be 'manual' or 'auto'" });
  }

  const allowed = ['name', 'logo_url', 'theme_color', 'contact_email', 'contact_phone', 'email_reply_to', 'automation_mode'];
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
  res.json(withoutSecrets(await db.prepare('SELECT * FROM tenants WHERE id = ?').get(tid)));
});

// PATCH /settings/email-provider — opt-in "bring your own Brevo account"
// (Tier 2 email identity). The API key is encrypted before storage and
// never returned to the client again, only a "configured: true/false" flag.
router.patch('/email-provider', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM tenants WHERE id = ?').get(tid);
  if (!existing) return res.status(404).json({ error: 'Tenant not found' });

  const { brevo_api_key, brevo_sender_email } = req.body;
  if (!brevo_api_key || !brevo_sender_email) {
    return res.status(400).json({ error: 'brevo_api_key and brevo_sender_email are both required' });
  }

  const encrypted = encrypt(brevo_api_key);
  await db.prepare(`
    UPDATE tenants SET own_brevo_api_key_encrypted = ?, own_brevo_sender_email = ? WHERE id = ?
  `).run(encrypted, brevo_sender_email, tid);

  res.json({ has_own_email_provider: true, own_brevo_sender_email: brevo_sender_email });
});

// DELETE /settings/email-provider — revert to the platform's shared Brevo
// account (Tier 1 / default).
router.delete('/email-provider', async (req, res) => {
  const tid = tenantId(req);
  await db.prepare(`
    UPDATE tenants SET own_brevo_api_key_encrypted = NULL, own_brevo_sender_email = NULL WHERE id = ?
  `).run(tid);
  res.json({ has_own_email_provider: false });
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
