const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

router.get('/', (req, res) => {
  const tid = tenantId(req);
  res.json(db.prepare('SELECT * FROM colleges WHERE tenant_id = ? ORDER BY name ASC').all(tid));
});

router.post('/', (req, res) => {
  const tid = tenantId(req);
  const { name, country, contact_person, contact_email, commission_percent, notes } = req.body;
  if (!name) return res.status(400).json({ error: 'name is required' });

  const id = randomUUID();
  db.prepare(`
    INSERT INTO colleges (id, tenant_id, name, country, contact_person, contact_email, commission_percent, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, name, country || null, contact_person || null, contact_email || null, commission_percent || null, notes || null);

  res.status(201).json(db.prepare('SELECT * FROM colleges WHERE id = ?').get(id));
});

router.patch('/:id', (req, res) => {
  const tid = tenantId(req);
  const existing = db.prepare('SELECT id FROM colleges WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'College not found' });

  const allowed = ['name', 'country', 'contact_person', 'contact_email', 'commission_percent', 'notes'];
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
  db.prepare(`UPDATE colleges SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  res.json(db.prepare('SELECT * FROM colleges WHERE id = ?').get(req.params.id));
});

router.delete('/:id', (req, res) => {
  const tid = tenantId(req);
  const result = db.prepare('DELETE FROM colleges WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'College not found' });
  res.status(204).send();
});

module.exports = router;
