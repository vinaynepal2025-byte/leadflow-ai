const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { generateJson } = require('../services/aiProvider');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

const NOTE_TAGS = [
  'objection', 'follow-up-needed', 'positive-signal', 'family-influence',
  'budget-concern', 'timeline-urgent', 'competitor-mentioned', 'general',
];

// Best-effort classification — a note is fully useful without this, so a
// slow/failed AI call should never block saving it. Runs synchronously
// before the insert (not fire-and-forget) because the whole point is to
// have the tags/sentiment on the row from the moment it's readable —
// but it's wrapped so any AI failure just leaves both fields null.
async function classifyNote(noteText) {
  try {
    const prompt = `You are classifying a counselor's note about an education-admission lead.

Note: "${noteText}"

Allowed tags (pick 1-3 that genuinely apply, fewer if only one clearly fits): ${NOTE_TAGS.join(', ')}

Respond ONLY with valid JSON, no other text, in exactly this shape:
{
  "tags": ["tag-from-the-allowed-list"],
  "sentiment": "positive"
}
(sentiment must be exactly one of: positive, neutral, negative)`;
    const result = await generateJson(prompt, { maxTokens: 1000 });
    const tags = Array.isArray(result.tags) ? result.tags.filter((t) => NOTE_TAGS.includes(t)) : [];
    const sentiment = ['positive', 'neutral', 'negative'].includes(result.sentiment) ? result.sentiment : null;
    return { tags: tags.length ? JSON.stringify(tags) : null, sentiment };
  } catch (err) {
    console.error('Note classification failed (non-fatal, note still saves):', err.message);
    return { tags: null, sentiment: null };
  }
}

// GET /lead-notes/sentiment-trend?lead_id=xxx — chronological sentiment
// series for charting, built from notes already classified at creation
// time (no extra AI calls here — just reading what's already stored).
router.get('/sentiment-trend', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  if (!lead_id) return res.status(400).json({ error: 'lead_id is required' });

  const rows = await db.prepare(
    "SELECT created_at, sentiment, tags FROM lead_notes WHERE tenant_id = ? AND lead_id = ? AND sentiment IS NOT NULL ORDER BY created_at ASC"
  ).all(tid, lead_id);

  const sentimentScore = { positive: 1, neutral: 0, negative: -1 };
  const points = rows.map((r) => ({
    at: r.created_at,
    sentiment: r.sentiment,
    score: sentimentScore[r.sentiment] ?? 0,
    tags: r.tags ? JSON.parse(r.tags) : [],
  }));

  res.json({ points, count: points.length });
});

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

  const { tags, sentiment } = await classifyNote(note_text);

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO lead_notes (id, tenant_id, lead_id, note_text, author_name, tags, sentiment)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, note_text, author_name || null, tags, sentiment);

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
