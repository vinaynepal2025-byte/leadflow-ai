const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /lead-notes?lead_id=xxx
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  if (!lead_id) return res.status(400).json({ error: 'lead_id is required' });
  const rows = await db.prepare(
    'SELECT * FROM lead_notes WHERE tenant_id = ? AND lead_id = ? ORDER BY pinned DESC, created_at DESC'
  ).all(tid, lead_id);
  res.json(rows);
});

// POST /lead-notes  { lead_id, note_text, author_name }
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, note_text, author_name } = req.body;
  if (!lead_id || !note_text) {
    return res.status(400).json({ error: 'lead_id and note_text are required' });
  }
  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found for this tenant' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO lead_notes (id, tenant_id, lead_id, note_text, author_name)
    VALUES (?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, note_text, author_name || null);

  res.status(201).json(await db.prepare('SELECT * FROM lead_notes WHERE id = ?').get(id));
});

// PATCH /lead-notes/:id  { note_text?, pinned? }
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM lead_notes WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Note not found' });

  const allowed = ['note_text', 'pinned'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) { updates.push(field + ' = ?'); values.push(req.body[field]); }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });
  values.push(tid, req.params.id);
  await db.prepare('UPDATE lead_notes SET ' + updates.join(', ') + ' WHERE tenant_id = ? AND id = ?').run(...values);

  res.json(await db.prepare('SELECT * FROM lead_notes WHERE id = ?').get(req.params.id));
});

// DELETE /lead-notes/:id
router.delete('/:id', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare('DELETE FROM lead_notes WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Note not found' });
  res.status(200).json({ deleted: true });
});

module.exports = router;
