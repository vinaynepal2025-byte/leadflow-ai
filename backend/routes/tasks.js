const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /tasks?assigned_to=Priya&status=pending
router.get('/', (req, res) => {
  const tid = tenantId(req);
  const { assigned_to, status } = req.query;
  let query = 'SELECT * FROM tasks WHERE tenant_id = ?';
  const params = [tid];
  if (assigned_to) {
    query += ' AND assigned_to = ?';
    params.push(assigned_to);
  }
  if (status) {
    query += ' AND status = ?';
    params.push(status);
  }
  query += ' ORDER BY due_at ASC';
  res.json(db.prepare(query).all(...params));
});

// POST /tasks — general task, optionally linked to a lead
router.post('/', (req, res) => {
  const tid = tenantId(req);
  const { title, due_at, assigned_to, lead_id, priority } = req.body;
  if (!title) return res.status(400).json({ error: 'title is required' });

  const id = randomUUID();
  db.prepare(`
    INSERT INTO tasks (id, tenant_id, title, due_at, assigned_to, lead_id, priority)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, title, due_at || null, assigned_to || null, lead_id || null, priority || 'normal');

  res.status(201).json(db.prepare('SELECT * FROM tasks WHERE id = ?').get(id));
});

// PATCH /tasks/:id
router.patch('/:id', (req, res) => {
  const tid = tenantId(req);
  const existing = db.prepare('SELECT * FROM tasks WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Task not found' });

  const allowed = ['title', 'due_at', 'status', 'assigned_to', 'priority'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) {
      updates.push(`${field} = ?`);
      values.push(req.body[field]);
    }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });
  values.push(tid, req.params.id);
  db.prepare(`UPDATE tasks SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  res.json(db.prepare('SELECT * FROM tasks WHERE id = ?').get(req.params.id));
});

module.exports = router;
