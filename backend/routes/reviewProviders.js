const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// A UPI VPA looks like name@bank -- not exhaustive, just catches obvious typos
// before they end up as an unusable payment link.
const UPI_RE = /^[\w.-]{2,256}@[a-zA-Z]{2,64}$/;

function withRating(row) {
  if (!row) return row;
  return {
    ...row,
    average_rating: row.rating_count > 0 ? Math.round((row.rating_sum / row.rating_count) * 10) / 10 : null,
  };
}

// GET /review-providers?college_id=xxx&active_only=true
// Public-facing list (what a lead sees when picking who to book a paid
// review call with) -- only surfaces verified + active providers unless
// the caller explicitly asks for everything (counselor/admin view).
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { college_id, active_only } = req.query;

  let query = 'SELECT * FROM review_providers WHERE tenant_id = ?';
  const params = [tid];
  if (college_id) { query += ' AND college_id = ?'; params.push(college_id); }
  if (active_only !== 'false') { query += ' AND active = true AND verified = true'; }
  query += ' ORDER BY rating_count DESC, created_at DESC';

  const rows = await db.prepare(query).all(...params);
  res.json(rows.map(withRating));
});

// POST /review-providers — self-serve registration (a student/alumnus signs
// up to offer paid review calls for their college). Starts unverified --
// a counselor/admin must verify before the provider appears to leads.
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { college_id, full_name, role, phone, upi_id, price_per_review, pricing_mode, rate_per_minute, bio } = req.body;

  if (!college_id || !full_name || !upi_id) {
    return res.status(400).json({ error: 'college_id, full_name, and upi_id are required' });
  }
  if (!UPI_RE.test(upi_id)) {
    return res.status(400).json({ error: 'upi_id does not look like a valid UPI ID (expected format: name@bank)' });
  }
  const mode = pricing_mode === 'per_minute' ? 'per_minute' : 'flat';
  if (mode === 'per_minute' && (!rate_per_minute || rate_per_minute <= 0)) {
    return res.status(400).json({ error: 'rate_per_minute must be a positive number for per_minute pricing_mode' });
  }
  const college = await db.prepare('SELECT id FROM colleges WHERE tenant_id = ? AND id = ?').get(tid, college_id);
  if (!college) return res.status(404).json({ error: 'College not found for this tenant' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO review_providers (id, tenant_id, college_id, full_name, role, phone, upi_id, price_per_review, pricing_mode, rate_per_minute, bio)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, college_id, full_name, role || 'student', phone || null, upi_id, price_per_review || null, mode, mode === 'per_minute' ? rate_per_minute : null, bio || null);

  res.status(201).json(withRating(await db.prepare('SELECT * FROM review_providers WHERE id = ?').get(id)));
});

// PATCH /review-providers/:id — admin control: verify, activate/deactivate,
// correct price. This is the "on/off per provider" lever; college-level
// on/off lives on colleges.peer_review_enabled.
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM review_providers WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Review provider not found' });

  if (req.body.upi_id !== undefined && !UPI_RE.test(req.body.upi_id)) {
    return res.status(400).json({ error: 'upi_id does not look like a valid UPI ID (expected format: name@bank)' });
  }
  if (req.body.pricing_mode !== undefined && !['flat', 'per_minute'].includes(req.body.pricing_mode)) {
    return res.status(400).json({ error: "pricing_mode must be 'flat' or 'per_minute'" });
  }

  const allowed = ['full_name', 'role', 'phone', 'upi_id', 'price_per_review', 'pricing_mode', 'rate_per_minute', 'bio', 'verified', 'active'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) { updates.push(`${field} = ?`); values.push(req.body[field]); }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });
  values.push(tid, req.params.id);
  await db.prepare(`UPDATE review_providers SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  res.json(withRating(await db.prepare('SELECT * FROM review_providers WHERE id = ?').get(req.params.id)));
});

router.delete('/:id', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare('DELETE FROM review_providers WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Review provider not found' });
  res.status(204).send();
});

module.exports = router;
