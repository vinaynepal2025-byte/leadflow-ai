const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

const VALID_TYPES = ['text', 'number', 'date', 'select'];

// GET /custom-fields — the tenant's field schema
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const rows = await db.prepare('SELECT * FROM custom_field_definitions WHERE tenant_id = ? ORDER BY created_at ASC').all(tid);
  res.json(rows.map((r) => ({ ...r, options: r.options ? JSON.parse(r.options) : null })));
});

// POST /custom-fields  { field_key, label, field_type, options? }
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { field_key, label, field_type, options } = req.body;

  if (!field_key || !label) return res.status(400).json({ error: 'field_key and label are required' });
  if (!/^[a-z0-9_]+$/.test(field_key)) {
    return res.status(400).json({ error: 'field_key must be lowercase letters, numbers, underscores only (e.g. ielts_score)' });
  }
  const type = field_type || 'text';
  if (!VALID_TYPES.includes(type)) return res.status(400).json({ error: `field_type must be one of: ${VALID_TYPES.join(', ')}` });
  if (type === 'select' && (!Array.isArray(options) || options.length === 0)) {
    return res.status(400).json({ error: 'select fields need a non-empty options array' });
  }

  const existing = await db.prepare('SELECT id FROM custom_field_definitions WHERE tenant_id = ? AND field_key = ?').get(tid, field_key);
  if (existing) return res.status(409).json({ error: `A field with key "${field_key}" already exists` });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO custom_field_definitions (id, tenant_id, field_key, label, field_type, options)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(id, tid, field_key, label, type, options ? JSON.stringify(options) : null);

  const created = await db.prepare('SELECT * FROM custom_field_definitions WHERE id = ?').get(id);
  res.status(201).json({ ...created, options: created.options ? JSON.parse(created.options) : null });
});

// DELETE /custom-fields/:id — removes the definition (existing lead values
// stay in their custom_fields JSON but no longer show as an editable field)
router.delete('/:id', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare('DELETE FROM custom_field_definitions WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Field not found' });
  res.status(204).send();
});

module.exports = router;
