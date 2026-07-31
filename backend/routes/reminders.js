const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /reminders?status=pending&due_before=2026-08-01
// Default: today's + overdue pending reminders — the "what should I do now" list
router.get('/', (req, res) => {
  const tid = tenantId(req);
  const { status, lead_id } = req.query;

  let query = 'SELECT * FROM reminders WHERE tenant_id = ?';
  const params = [tid];

  if (status) {
    query += ' AND status = ?';
    params.push(status);
  }
  if (lead_id) {
    query += ' AND lead_id = ?';
    params.push(lead_id);
  }
  query += ' ORDER BY due_at ASC';

  const rows = db.prepare(query).all(...params);
  res.json(rows);
});

// POST /reminders — create a follow-up reminder for a lead
router.post('/', (req, res) => {
  const tid = tenantId(req);
  const { lead_id, title, due_at, assigned_to } = req.body;

  if (!lead_id || !title || !due_at) {
    return res.status(400).json({ error: 'lead_id, title, and due_at are required' });
  }
  const lead = db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found for this tenant' });

  const id = randomUUID();
  db.prepare(`
    INSERT INTO reminders (id, tenant_id, lead_id, title, due_at, assigned_to)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, title, due_at, assigned_to || null);

  res.status(201).json(db.prepare('SELECT * FROM reminders WHERE id = ?').get(id));
});

// PATCH /reminders/:id — mark done / missed / reschedule
router.patch('/:id', (req, res) => {
  const tid = tenantId(req);
  const existing = db.prepare('SELECT * FROM reminders WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Reminder not found' });

  const allowed = ['title', 'due_at', 'status', 'assigned_to'];
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
  db.prepare(`UPDATE reminders SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  res.json(db.prepare('SELECT * FROM reminders WHERE id = ?').get(req.params.id));
});

// DELETE /reminders/:id
router.delete('/:id', (req, res) => {
  const tid = tenantId(req);
  const result = db.prepare('DELETE FROM reminders WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Reminder not found' });
  res.status(204).send();
});

module.exports = router;
