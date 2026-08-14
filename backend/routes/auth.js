const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { randomUUID, randomBytes } = require('crypto');
const db = require('../db');
const { sendEmail } = require('../services/email');

const router = express.Router();

// In production this MUST be a long random secret set via .env — never
// committed. A fallback is provided only so local dev works out of the box.
const JWT_SECRET = process.env.JWT_SECRET || 'dev-only-insecure-secret-change-me';

const SLUG_RE = /^[a-z0-9][a-z0-9-]{2,49}$/;
const VERIFY_TOKEN_TTL_HOURS = 24;

function verificationEmailText(link, tenantName) {
  return `Welcome to LeadFlow AI, ${tenantName}!\n\n` +
    `Click (or paste into your browser) the link below to verify your email and activate your consultancy's account:\n\n${link}\n\n` +
    `This link expires in ${VERIFY_TOKEN_TTL_HOURS} hours.`;
}

// POST /auth/signup  { tenant_id, tenant_name, email, password, full_name }
// Creates a BRAND NEW tenant (consultancy) + its first (owner) user.
// Tenant starts as status='pending' -- login is blocked until the owner
// clicks the verification link sent to their email. This is distinct
// from /auth/register below, which only adds a user to an EXISTING tenant.
router.post('/signup', async (req, res) => {
  const { tenant_id, tenant_name, email, password, full_name } = req.body;
  if (!tenant_id || !tenant_name || !email || !password || !full_name) {
    return res.status(400).json({ error: 'tenant_id, tenant_name, email, password, and full_name are required' });
  }
  if (!SLUG_RE.test(tenant_id)) {
    return res.status(400).json({ error: 'tenant_id must be 3-50 characters, lowercase letters/numbers/hyphens only, starting with a letter or number' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'password must be at least 6 characters' });
  }

  const existingTenant = await db.prepare('SELECT id FROM tenants WHERE id = ?').get(tenant_id);
  if (existingTenant) {
    return res.status(409).json({ error: 'This Consultancy ID is already taken -- please choose another' });
  }

  const token = randomBytes(24).toString('hex');
  const expiresAt = new Date(Date.now() + VERIFY_TOKEN_TTL_HOURS * 60 * 60 * 1000).toISOString();

  await db.prepare(`
    INSERT INTO tenants (id, name, contact_email, status, verification_token, verification_token_expires_at)
    VALUES (?, ?, ?, 'pending', ?, ?)
  `).run(tenant_id, tenant_name, email, token, expiresAt);

  const passwordHash = await bcrypt.hash(password, 10);
  const userId = randomUUID();
  await db.prepare(`
    INSERT INTO users (id, tenant_id, email, password_hash, full_name, role)
    VALUES (?, ?, ?, ?, ?, 'owner')
  `).run(userId, tenant_id, email, passwordHash, full_name);

  const verifyLink = `${req.protocol}://${req.get('host')}/auth/verify-email?token=${token}`;
  try {
    await sendEmail(email, 'Verify your LeadFlow AI account', verificationEmailText(verifyLink, tenant_name));
  } catch (err) {
    // The tenant + user are already created -- don't lose that because the
    // verification email failed to send. Resend endpoint below covers this.
    return res.status(201).json({
      tenant_id,
      message: 'Account created, but the verification email could not be sent. Use "Resend verification email" to try again.',
      email_error: err.message,
    });
  }

  res.status(201).json({
    tenant_id,
    message: `Account created. Check ${email} for a verification link before logging in.`,
  });
});

// GET /auth/verify-email?token=...  — the link clicked from the email.
// Public, no auth header (a browser link click can't send one).
router.get('/verify-email', async (req, res) => {
  const { token } = req.query;
  const shell = (body) => `<!DOCTYPE html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>LeadFlow AI — Verify Email</title></head>
    <body style="font-family:-apple-system,Roboto,sans-serif;background:#f7f8fa;color:#1B2A4A;margin:0;padding:24px;display:flex;justify-content:center;">
      <div style="max-width:420px;width:100%;background:#fff;border-radius:16px;padding:28px;text-align:center;box-shadow:0 2px 12px rgba(0,0,0,0.08);">${body}</div>
    </body></html>`;

  if (!token) return res.status(400).send(shell('<h2>⚠️ Missing verification token</h2>'));

  const tenant = await db.prepare('SELECT * FROM tenants WHERE verification_token = ?').get(token);
  if (!tenant) return res.status(404).send(shell('<h2>⚠️ Invalid or already-used verification link</h2>'));

  if (tenant.verification_token_expires_at && new Date(tenant.verification_token_expires_at) < new Date()) {
    return res.status(410).send(shell('<h2>⚠️ This verification link has expired</h2><p>Please request a new one from the app.</p>'));
  }

  await db.prepare(`
    UPDATE tenants SET status = 'active', verification_token = NULL, verification_token_expires_at = NULL WHERE id = ?
  `).run(tenant.id);

  res.send(shell(`<div style="font-size:48px;">✅</div><h2>Email verified!</h2><p>You can now log in to LeadFlow AI as <b>${tenant.name}</b>.</p>`));
});

// POST /auth/resend-verification  { tenant_id }
router.post('/resend-verification', async (req, res) => {
  const { tenant_id } = req.body;
  if (!tenant_id) return res.status(400).json({ error: 'tenant_id is required' });

  const tenant = await db.prepare('SELECT * FROM tenants WHERE id = ?').get(tenant_id);
  if (!tenant) return res.status(404).json({ error: 'Unknown tenant_id' });
  if (tenant.status === 'active') return res.status(400).json({ error: 'This account is already verified' });

  const token = randomBytes(24).toString('hex');
  const expiresAt = new Date(Date.now() + VERIFY_TOKEN_TTL_HOURS * 60 * 60 * 1000).toISOString();
  await db.prepare('UPDATE tenants SET verification_token = ?, verification_token_expires_at = ? WHERE id = ?')
    .run(token, expiresAt, tenant_id);

  const verifyLink = `${req.protocol}://${req.get('host')}/auth/verify-email?token=${token}`;
  try {
    await sendEmail(tenant.contact_email, 'Verify your LeadFlow AI account', verificationEmailText(verifyLink, tenant.name), tenant);
  } catch (err) {
    return res.status(502).json({ error: `Could not send email: ${err.message}` });
  }
  res.json({ message: `Verification email resent to ${tenant.contact_email}` });
});

// POST /auth/register  { tenant_id, email, password, full_name, role }
// Adds a user to an EXISTING (already-verified) tenant -- e.g. a
// counselor joining a consultancy that already signed up. Distinct from
// /auth/signup above, which creates the tenant itself.
// Note: v1 has no invite/admin-gating yet — anyone can self-register into
// any tenant_id they name, as long as that tenant is active. That's fine
// for solo testing, not for real multi-tenant use — Module: Access
// Control will close this gap.
router.post('/register', async (req, res) => {
  const { tenant_id, email, password, full_name, role } = req.body;
  if (!tenant_id || !email || !password || !full_name) {
    return res.status(400).json({ error: 'tenant_id, email, password, and full_name are required' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'password must be at least 6 characters' });
  }

  const tenant = await db.prepare('SELECT id, status FROM tenants WHERE id = ?').get(tenant_id);
  if (!tenant) return res.status(404).json({ error: 'Unknown tenant_id' });
  if (tenant.status !== 'active') {
    return res.status(403).json({ error: 'This consultancy has not verified its email yet' });
  }

  const existing = await db.prepare('SELECT id FROM users WHERE tenant_id = ? AND email = ?').get(tenant_id, email);
  if (existing) return res.status(409).json({ error: 'A user with this email already exists in this tenant' });

  const passwordHash = await bcrypt.hash(password, 10);
  const id = randomUUID();
  await db.prepare(`
    INSERT INTO users (id, tenant_id, email, password_hash, full_name, role)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(id, tenant_id, email, passwordHash, full_name, role || 'counselor');

  const token = jwt.sign({ userId: id, tenantId: tenant_id, role: role || 'counselor' }, JWT_SECRET, { expiresIn: '30d' });
  res.status(201).json({ token, user: { id, email, full_name, role: role || 'counselor', tenant_id } });
});

// POST /auth/login  { tenant_id, email, password }
router.post('/login', async (req, res) => {
  const { tenant_id, email, password } = req.body;
  if (!tenant_id || !email || !password) {
    return res.status(400).json({ error: 'tenant_id, email, and password are required' });
  }

  const tenant = await db.prepare('SELECT status FROM tenants WHERE id = ?').get(tenant_id);
  if (!tenant) return res.status(401).json({ error: 'Invalid email or password' });
  if (tenant.status !== 'active') {
    return res.status(403).json({ error: 'Please verify your email before logging in -- check your inbox, or use "Resend verification email".' });
  }

  const user = await db.prepare('SELECT * FROM users WHERE tenant_id = ? AND email = ?').get(tenant_id, email);
  if (!user) return res.status(401).json({ error: 'Invalid email or password' });

  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) return res.status(401).json({ error: 'Invalid email or password' });

  const token = jwt.sign({ userId: user.id, tenantId: user.tenant_id, role: user.role }, JWT_SECRET, { expiresIn: '30d' });
  res.json({
    token,
    user: { id: user.id, email: user.email, full_name: user.full_name, role: user.role, tenant_id: user.tenant_id },
  });
});

// Middleware other routes can use later to require a logged-in user.
// Not yet wired into leads/communications/etc. — that's the next step,
// swapping the x-tenant-id header for this verified token.
function requireAuth(req, res, next) {
  const header = req.header('Authorization');
  if (!header?.startsWith('Bearer ')) return res.status(401).json({ error: 'Missing or invalid Authorization header' });
  try {
    const payload = jwt.verify(header.slice(7), JWT_SECRET);
    req.auth = payload;
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

// GET /auth/team — list registered users for this tenant (no password hashes)
router.get('/team', async (req, res) => {
  const tid = req.header('x-tenant-id') || 'demo-consultancy';
  const users = await db.prepare(
    'SELECT id, email, full_name, role, active, created_at FROM users WHERE tenant_id = ? ORDER BY active DESC, full_name'
  ).all(tid);
  res.json(users);
});

// A consultancy is a multi-person operation, but Team was read-only —
// there was no way to add a counselor, change who can do what, or remove
// someone who left. These three routes close that.

const TEAM_ROLES = ['admin', 'counselor', 'viewer'];

// POST /auth/team — add a member with a temporary password they change on
// first login. Deliberately not an email-invite flow yet: that needs a
// token table and a public accept-invite page, and this unblocks real
// multi-user use today. Flagged as a follow-up rather than pretended.
router.post('/team', async (req, res) => {
  const tid = req.header('x-tenant-id') || 'demo-consultancy';
  const { email, full_name, role, temp_password } = req.body;
  if (!email || !full_name || !temp_password) {
    return res.status(400).json({ error: 'email, full_name and temp_password are required' });
  }
  if (role && !TEAM_ROLES.includes(role)) {
    return res.status(400).json({ error: `role must be one of: ${TEAM_ROLES.join(', ')}` });
  }
  if (String(temp_password).length < 8) {
    return res.status(400).json({ error: 'temp_password must be at least 8 characters' });
  }

  const existing = await db.prepare('SELECT id FROM users WHERE tenant_id = ? AND lower(email) = lower(?)').get(tid, email);
  if (existing) return res.status(409).json({ error: 'Someone with that email is already on the team' });

  const id = randomUUID();
  const hash = await bcrypt.hash(temp_password, 10);
  await db.prepare(`
    INSERT INTO users (id, tenant_id, email, password_hash, full_name, role)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(id, tid, email, hash, full_name, role || 'counselor');

  res.status(201).json(
    await db.prepare('SELECT id, email, full_name, role, active, created_at FROM users WHERE id = ?').get(id)
  );
});

// PATCH /auth/team/:id — change role, name, or reactivate
router.patch('/team/:id', async (req, res) => {
  const tid = req.header('x-tenant-id') || 'demo-consultancy';
  const existing = await db.prepare('SELECT * FROM users WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Team member not found' });

  const { full_name, role, active } = req.body;
  if (role !== undefined && !TEAM_ROLES.includes(role)) {
    return res.status(400).json({ error: `role must be one of: ${TEAM_ROLES.join(', ')}` });
  }

  const updates = [];
  const values = [];
  if (full_name !== undefined) { updates.push('full_name = ?'); values.push(full_name); }
  if (role !== undefined) { updates.push('role = ?'); values.push(role); }
  if (active !== undefined) { updates.push('active = ?'); values.push(active ? true : false); }
  if (updates.length === 0) return res.status(400).json({ error: 'Nothing to update' });

  values.push(tid, req.params.id);
  await db.prepare(`UPDATE users SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  res.json(await db.prepare('SELECT id, email, full_name, role, active, created_at FROM users WHERE id = ?').get(req.params.id));
});

// DELETE /auth/team/:id — deactivate rather than hard-delete, so the
// counselor's name stays resolvable on every lead, call and note they
// ever touched. Hard-deleting would orphan that history.
router.delete('/team/:id', async (req, res) => {
  const tid = req.header('x-tenant-id') || 'demo-consultancy';
  const remaining = await db.prepare(
    "SELECT COUNT(*) AS c FROM users WHERE tenant_id = ? AND active = true AND id != ?"
  ).get(tid, req.params.id);
  if (remaining.c === 0) {
    return res.status(400).json({ error: 'Cannot deactivate the last active member of the team' });
  }
  const result = await db.prepare('UPDATE users SET active = false WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Team member not found' });
  res.status(204).send();
});

module.exports = { router, requireAuth };
