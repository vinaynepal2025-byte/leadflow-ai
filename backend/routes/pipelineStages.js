const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /pipeline-stages
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  res.json(await db.prepare('SELECT * FROM pipeline_stages WHERE tenant_id = ? ORDER BY position ASC').all(tid));
});

// POST /pipeline-stages  { name, color? }  — appended at the end
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { name, color } = req.body;
  if (!name) return res.status(400).json({ error: 'name is required' });

  const maxPosRow = await db.prepare('SELECT COALESCE(MAX(position), -1) AS m FROM pipeline_stages WHERE tenant_id = ?').get(tid);
  const maxPos = maxPosRow.m;
  const id = randomUUID();
  await db.prepare('INSERT INTO pipeline_stages (id, tenant_id, name, position, color) VALUES (?, ?, ?, ?, ?)')
    .run(id, tid, name, maxPos + 1, color || '#607D8B');

  res.status(201).json(await db.prepare('SELECT * FROM pipeline_stages WHERE id = ?').get(id));
});

// PATCH /pipeline-stages/:id  { name?, color? }
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM pipeline_stages WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Stage not found' });

  const allowed = ['name', 'color'];
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
  await db.prepare(`UPDATE pipeline_stages SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  res.json(await db.prepare('SELECT * FROM pipeline_stages WHERE id = ?').get(req.params.id));
});

// PUT /pipeline-stages/reorder  { ordered_ids: [id1, id2, ...] }
// Whole-list reorder — simplest correct way to support drag-and-drop reordering.
router.put('/reorder', async (req, res) => {
  const tid = tenantId(req);
  const { ordered_ids } = req.body;
  if (!Array.isArray(ordered_ids)) return res.status(400).json({ error: 'ordered_ids must be an array' });

  const update = await db.prepare('UPDATE pipeline_stages SET position = ? WHERE tenant_id = ? AND id = ?');
  ordered_ids.forEach((id, i) => update.run(i, tid, id));

  res.json(await db.prepare('SELECT * FROM pipeline_stages WHERE tenant_id = ? ORDER BY position ASC').all(tid));
});

// DELETE /pipeline-stages/:id
// Note: leads currently sitting in this stage keep their stage string as-is
// (a lead's `stage` field is just text) — deleting a stage definition
// doesn't retroactively move leads. That's a deliberate v1 choice: the
// counselor sees the historical value and can reassign it manually,
// rather than the system silently reassigning people.
router.delete('/:id', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare('DELETE FROM pipeline_stages WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Stage not found' });
  res.status(204).send();
});

module.exports = router;
