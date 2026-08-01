const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /knowledge?category=Visa+Process&q=schengen
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { category, q } = req.query;
  let query = 'SELECT * FROM knowledge_articles WHERE tenant_id = ?';
  const params = [tid];
  if (category) {
    query += ' AND category = ?';
    params.push(category);
  }
  if (q) {
    query += ' AND (title LIKE ? OR content LIKE ?)';
    params.push(`%${q}%`, `%${q}%`);
  }
  query += ' ORDER BY updated_at DESC';
  res.json(await db.prepare(query).all(...params));
});

// GET /knowledge/:id
router.get('/:id', async (req, res) => {
  const tid = tenantId(req);
  const row = await db.prepare('SELECT * FROM knowledge_articles WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!row) return res.status(404).json({ error: 'Article not found' });
  res.json(row);
});

// POST /knowledge
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { title, content, category } = req.body;
  if (!title || !content) return res.status(400).json({ error: 'title and content are required' });

  const id = randomUUID();
  await db.prepare('INSERT INTO knowledge_articles (id, tenant_id, title, content, category) VALUES (?, ?, ?, ?, ?)')
    .run(id, tid, title, content, category || null);
  res.status(201).json(await db.prepare('SELECT * FROM knowledge_articles WHERE id = ?').get(id));
});

// PATCH /knowledge/:id
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM knowledge_articles WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Article not found' });

  const allowed = ['title', 'content', 'category'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) {
      updates.push(`${field} = ?`);
      values.push(req.body[field]);
    }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });
  updates.push("updated_at = datetime('now')");
  values.push(tid, req.params.id);
  await db.prepare(`UPDATE knowledge_articles SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  res.json(await db.prepare('SELECT * FROM knowledge_articles WHERE id = ?').get(req.params.id));
});

// DELETE /knowledge/:id
router.delete('/:id', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare('DELETE FROM knowledge_articles WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Article not found' });
  res.status(204).send();
});

module.exports = router;
