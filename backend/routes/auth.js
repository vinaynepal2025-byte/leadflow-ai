const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { randomUUID, randomBytes } = require('crypto');
const db = require('../db');
const { sendEmail } = require('../services/email');
const { requireRole } = require('../middleware/auth');

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

  // Was missing entirely before this fix -- a deactivated team member
  // (users.active = false, e.g. via PATCH /auth/team/:id) could still
  // log in as long as they knew their password. Also covers an invited
  // member who hasn't accepted their invite yet (see POST /team below):
  // they're created with active=false and an unguessable password until
  // they set a real one via /auth/accept-invite.
  if (user.active === false) {
    return res.status(403).json({ error: 'This account is inactive. Contact your admin.' });
  }

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

// Same shell wrapper as verify-email's HTML pages -- used by the two
// invite-acceptance routes below, which render actual pages (a browser
// link click, not an API call) since there's no separate web frontend
// this could hand off to.
function pageShell(body) {
  return `<!DOCTYPE html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>LeadFlow AI — Team Invite</title></head>
    <body style="font-family:-apple-system,Roboto,sans-serif;background:#f7f8fa;color:#1B2A4A;margin:0;padding:24px;display:flex;justify-content:center;">
      <div style="max-width:420px;width:100%;background:#fff;border-radius:16px;padding:28px;">${body}</div>
    </body></html>`;
}

const INVITE_TOKEN_TTL_HOURS = 72;

function inviteEmailText(link, fullName, tenantName) {
  return `Hi ${fullName},\n\n` +
    `You've been added to ${tenantName}'s LeadFlow AI team. Click (or paste into your browser) the link below to set your password and get started:\n\n${link}\n\n` +
    `This link expires in ${INVITE_TOKEN_TTL_HOURS} hours. If it expires, ask your admin to resend the invite.`;
}

// POST /auth/team -- creates a team member and emails them an invite
// link to set their own password, rather than an admin picking a
// temp_password for them (the deliberate scope-cut flagged since the
// roles feature shipped). temp_password is kept as an OPTIONAL fallback
// for the rare case email delivery isn't configured for this tenant --
// if provided, the account is created active immediately with that
// password, same as before; if omitted, the invite-link flow runs.
router.post('/team', requireRole('admin'), async (req, res) => {
  const tid = req.header('x-tenant-id') || 'demo-consultancy';
  const { email, full_name, role, temp_password } = req.body;
  if (!email || !full_name) {
    return res.status(400).json({ error: 'email and full_name are required' });
  }
  if (role && !TEAM_ROLES.includes(role)) {
    return res.status(400).json({ error: `role must be one of: ${TEAM_ROLES.join(', ')}` });
  }
  if (temp_password && String(temp_password).length < 8) {
    return res.status(400).json({ error: 'temp_password must be at least 8 characters' });
  }

  const existing = await db.prepare('SELECT id FROM users WHERE tenant_id = ? AND lower(email) = lower(?)').get(tid, email);
  if (existing) return res.status(409).json({ error: 'Someone with that email is already on the team' });

  const id = randomUUID();

  if (temp_password) {
    // Fallback path -- unchanged from before, account is usable right away.
    const hash = await bcrypt.hash(temp_password, 10);
    await db.prepare(`
      INSERT INTO users (id, tenant_id, email, password_hash, full_name, role, active)
      VALUES (?, ?, ?, ?, ?, ?, true)
    `).run(id, tid, email, hash, full_name, role || 'counselor');
    return res.status(201).json(
      await db.prepare('SELECT id, email, full_name, role, active, created_at FROM users WHERE id = ?').get(id)
    );
  }

  // Invite-link path -- account exists but can't log in (active=false,
  // and the password hash is a bcrypt hash of a random value nobody
  // knows) until the invite link is used.
  const unusablePassword = await bcrypt.hash(randomBytes(24).toString('hex'), 10);
  const token = randomBytes(24).toString('hex');
  const expiresAt = new Date(Date.now() + INVITE_TOKEN_TTL_HOURS * 60 * 60 * 1000).toISOString();

  await db.prepare(`
    INSERT INTO users (id, tenant_id, email, password_hash, full_name, role, active, invite_token, invite_token_expires_at)
    VALUES (?, ?, ?, ?, ?, ?, false, ?, ?)
  `).run(id, tid, email, unusablePassword, full_name, role || 'counselor', token, expiresAt);

  const tenant = await db.prepare('SELECT name FROM tenants WHERE id = ?').get(tid);
  const inviteLink = `${req.protocol}://${req.get('host')}/auth/accept-invite?token=${token}`;

  try {
    await sendEmail(email, `You're invited to join ${tenant?.name || tid} on LeadFlow AI`, inviteEmailText(inviteLink, full_name, tenant?.name || tid));
  } catch (err) {
    // Same graceful-degradation as /signup: the account exists either
    // way, so hand the admin the raw link to share manually rather than
    // losing the invite because email delivery failed.
    return res.status(201).json({
      ...(await db.prepare('SELECT id, email, full_name, role, active, created_at FROM users WHERE id = ?').get(id)),
      message: 'Team member created, but the invite email could not be sent.',
      invite_link: inviteLink,
      email_error: err.message,
    });
  }

  res.status(201).json({
    ...(await db.prepare('SELECT id, email, full_name, role, active, created_at FROM users WHERE id = ?').get(id)),
    message: `Invite sent to ${email}.`,
  });
});

// POST /auth/team/:id/resend-invite -- for an expired or lost invite link.
router.post('/team/:id/resend-invite', requireRole('admin'), async (req, res) => {
  const tid = req.header('x-tenant-id') || 'demo-consultancy';
  const user = await db.prepare('SELECT * FROM users WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!user) return res.status(404).json({ error: 'Team member not found' });
  if (user.active) return res.status(400).json({ error: 'This team member has already accepted their invite.' });

  const token = randomBytes(24).toString('hex');
  const expiresAt = new Date(Date.now() + INVITE_TOKEN_TTL_HOURS * 60 * 60 * 1000).toISOString();
  await db.prepare('UPDATE users SET invite_token = ?, invite_token_expires_at = ? WHERE id = ?').run(token, expiresAt, user.id);

  const tenant = await db.prepare('SELECT name FROM tenants WHERE id = ?').get(tid);
  const inviteLink = `${req.protocol}://${req.get('host')}/auth/accept-invite?token=${token}`;

  try {
    await sendEmail(user.email, `You're invited to join ${tenant?.name || tid} on LeadFlow AI`, inviteEmailText(inviteLink, user.full_name, tenant?.name || tid));
    res.json({ message: `Invite resent to ${user.email}.` });
  } catch (err) {
    res.json({ message: 'Invite regenerated, but the email could not be sent.', invite_link: inviteLink, email_error: err.message });
  }
});

// GET /auth/accept-invite?token=... -- the link clicked from the invite
// email. Public (a browser link click can't send an Authorization
// header), so this is added to middleware/auth.js's PUBLIC_PREFIXES.
router.get('/accept-invite', async (req, res) => {
  const { token } = req.query;
  if (!token) return res.status(400).send(pageShell('<h2>⚠️ Missing invite token</h2>'));

  const user = await db.prepare('SELECT full_name, invite_token_expires_at FROM users WHERE invite_token = ?').get(token);
  if (!user) return res.status(404).send(pageShell('<h2>⚠️ Invalid or already-used invite link</h2>'));
  if (user.invite_token_expires_at && new Date(user.invite_token_expires_at) < new Date()) {
    return res.status(410).send(pageShell('<h2>⚠️ This invite link has expired</h2><p>Ask your admin to resend it.</p>'));
  }

  res.send(pageShell(`
    <h2>Welcome, ${user.full_name}!</h2>
    <p style="color:#5B6478;font-size:14px;">Set a password to activate your LeadFlow AI account.</p>
    <form method="POST" action="/auth/accept-invite" style="margin-top:16px;">
      <input type="hidden" name="token" value="${token}">
      <label style="font-size:13px;">Password (min 6 characters)</label>
      <input type="password" name="password" minlength="6" required style="width:100%;box-sizing:border-box;padding:10px;margin:6px 0 14px;border:1px solid #ddd;border-radius:8px;">
      <label style="font-size:13px;">Confirm password</label>
      <input type="password" name="confirm_password" minlength="6" required style="width:100%;box-sizing:border-box;padding:10px;margin:6px 0 18px;border:1px solid #ddd;border-radius:8px;">
      <button type="submit" style="width:100%;padding:12px;background:#1B2A4A;color:#fff;border:none;border-radius:8px;font-weight:600;">Activate account</button>
    </form>
  `));
});

// POST /auth/accept-invite -- submitted by the form above. Also public,
// same reason. Parses application/x-www-form-urlencoded since it's a
// plain HTML form post, not a JSON API call.
router.post('/accept-invite', express.urlencoded({ extended: false }), async (req, res) => {
  const { token, password, confirm_password } = req.body;
  if (!token) return res.status(400).send(pageShell('<h2>⚠️ Missing invite token</h2>'));

  const user = await db.prepare('SELECT id, invite_token_expires_at FROM users WHERE invite_token = ?').get(token);
  if (!user) return res.status(404).send(pageShell('<h2>⚠️ Invalid or already-used invite link</h2>'));
  if (user.invite_token_expires_at && new Date(user.invite_token_expires_at) < new Date()) {
    return res.status(410).send(pageShell('<h2>⚠️ This invite link has expired</h2><p>Ask your admin to resend it.</p>'));
  }
  if (!password || password.length < 6) {
    return res.status(400).send(pageShell('<h2>⚠️ Password must be at least 6 characters</h2><p><a href="?token=' + token + '">Go back</a></p>'));
  }
  if (password !== confirm_password) {
    return res.status(400).send(pageShell('<h2>⚠️ Passwords don\'t match</h2><p><a href="?token=' + token + '">Go back</a></p>'));
  }

  const hash = await bcrypt.hash(password, 10);
  await db.prepare(`
    UPDATE users SET password_hash = ?, active = true, invite_token = NULL, invite_token_expires_at = NULL WHERE id = ?
  `).run(hash, user.id);

  res.send(pageShell('<div style="font-size:48px;text-align:center;">✅</div><h2 style="text-align:center;">Account activated!</h2><p style="text-align:center;color:#5B6478;">You can now log in to LeadFlow AI from the app.</p>'));
});

// PATCH /auth/team/:id — change role, name, or reactivate
router.patch('/team/:id', requireRole('admin'), async (req, res) => {
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
router.delete('/team/:id', requireRole('admin'), async (req, res) => {
  const tid = req.header('x-tenant-id') || 'demo-consultancy';

  // Guard against self-lockout. Discovered the hard way during live
  // testing: the last-active check alone didn't stop the account owner
  // from deactivating themselves while other members existed, which
  // would leave them unable to log back in and fix it.
  if (req.user?.id === req.params.id) {
    return res.status(400).json({ error: 'You cannot deactivate your own account — ask another admin to do it' });
  }

  const target = await db.prepare('SELECT id, role FROM users WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!target) return res.status(404).json({ error: 'Team member not found' });

  const remainingAdmins = await db.prepare(
    "SELECT COUNT(*) AS c FROM users WHERE tenant_id = ? AND active = true AND role = 'admin' AND id != ?"
  ).get(tid, req.params.id);
  if (target.role === 'admin' && remainingAdmins.c === 0) {
    return res.status(400).json({ error: 'Cannot deactivate the last admin — promote someone else first' });
  }

  const remaining = await db.prepare(
    "SELECT COUNT(*) AS c FROM users WHERE tenant_id = ? AND active = true AND id != ?"
  ).get(tid, req.params.id);
  if (remaining.c === 0) {
    return res.status(400).json({ error: 'Cannot deactivate the last active member of the team' });
  }

  await db.prepare('UPDATE users SET active = false WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  res.status(204).send();
});

module.exports = { router, requireAuth };
