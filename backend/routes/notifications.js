const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

/// Reusable helper — other route files call this directly (not via HTTP)
/// to raise a notification, e.g. when a reminder becomes overdue or a
/// document is rejected. Kept as a plain function so it has zero request
/// overhead when called from inside another route handler.
async function createNotification(tenantId, { userId, title, body, linkType, linkId }) {
  const id = randomUUID();
  await db.prepare(`
    INSERT INTO notifications (id, tenant_id, user_id, title, body, link_type, link_id)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(id, tenantId, userId || null, title, body || null, linkType || null, linkId || null);
  return id;
}

// GET /notifications?unread_only=true
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { unread_only } = req.query;
  const query = unread_only === 'true'
    ? 'SELECT * FROM notifications WHERE tenant_id = ? AND read = 0 ORDER BY created_at DESC'
    : 'SELECT * FROM notifications WHERE tenant_id = ? ORDER BY created_at DESC LIMIT 100';
  res.json(await db.prepare(query).all(tid));
});

// GET /notifications/unread-count — for a badge icon
router.get('/unread-count', async (req, res) => {
  const tid = tenantId(req);
  const countRow = await db.prepare('SELECT COUNT(*) AS c FROM notifications WHERE tenant_id = ? AND read = 0').get(tid);
  const count = countRow.c;
  res.json({ count });
});

// PATCH /notifications/:id  { read: true }
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  await db.prepare('UPDATE notifications SET read = ? WHERE tenant_id = ? AND id = ?')
    .run(req.body.read ? 1 : 0, tid, req.params.id);
  res.json({ ok: true });
});

// POST /notifications/read-all
router.post('/read-all', async (req, res) => {
  const tid = tenantId(req);
  await db.prepare('UPDATE notifications SET read = 1 WHERE tenant_id = ?').run(tid);
  res.json({ ok: true });
});

module.exports = { router, createNotification };
