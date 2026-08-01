const express = require('express');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /calendar?from=2026-08-01&to=2026-08-31
// Combines Task Manager and Reminder Engine due dates into one feed —
// Calendar is a read-only projection over data that already exists, not
// a new store of its own (same principle as Audit Center).
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const from = req.query.from || new Date().toISOString().slice(0, 10);
  const to = req.query.to || new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10);

  const tasks = await db.prepare(`
    SELECT id, title, due_at, status, 'task' AS type, lead_id
    FROM tasks WHERE tenant_id = ? AND due_at BETWEEN ? AND ? AND status = 'pending'
  `).all(tid, from, to + 'T23:59:59');

  const reminders = await db.prepare(`
    SELECT id, title, due_at, status, 'reminder' AS type, lead_id
    FROM reminders WHERE tenant_id = ? AND due_at BETWEEN ? AND ? AND status = 'pending'
  `).all(tid, from, to + 'T23:59:59');

  const combined = [...tasks, ...reminders].sort((a, b) => (a.due_at > b.due_at ? 1 : -1));
  res.json(combined);
});

module.exports = router;
