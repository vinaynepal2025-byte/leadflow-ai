const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

// In production this MUST be a long random secret set via .env — never
// committed. A fallback is provided only so local dev works out of the box.
const JWT_SECRET = process.env.JWT_SECRET || 'dev-only-insecure-secret-change-me';

// POST /auth/register  { tenant_id, email, password, full_name, role }
// Note: v1 has no invite/admin-gating yet — anyone can self-register into
// any tenant_id they name. That's fine for solo testing, not for real
// multi-tenant use — Module: Access Control will close this gap.
router.post('/register', async (req, res) => {
  const { tenant_id, email, password, full_name, role } = req.body;
  if (!tenant_id || !email || !password || !full_name) {
    return res.status(400).json({ error: 'tenant_id, email, password, and full_name are required' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'password must be at least 6 characters' });
  }

  const tenant = await db.prepare('SELECT id FROM tenants WHERE id = ?').get(tenant_id);
  if (!tenant) return res.status(404).json({ error: 'Unknown tenant_id' });

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
  const users = await db.prepare('SELECT id, email, full_name, role, created_at FROM users WHERE tenant_id = ?').all(tid);
  res.json(users);
});

module.exports = { router, requireAuth };
