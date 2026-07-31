const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { randomUUID } = require('crypto');
const db = require('../db');
const { generateText } = require('../services/aiProvider');

const router = express.Router();

const UPLOAD_DIR = path.join(__dirname, '..', 'uploads', 'voice-notes');
if (!fs.existsSync(UPLOAD_DIR)) fs.mkdirSync(UPLOAD_DIR, { recursive: true });

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, UPLOAD_DIR),
  filename: (req, file, cb) => cb(null, `${randomUUID()}-${file.originalname}`),
});
const upload = multer({ storage, limits: { fileSize: 25 * 1024 * 1024 } });

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// POST /voice-notes  (multipart: file=<audio>, lead_id, recorded_by)
// Note: this stores the audio recording and lets you attach a transcript
// yourself (v1). Automatic speech-to-text needs a dedicated transcription
// API key this sandbox doesn't have configured — same honest pattern as
// WhatsApp/Email/AI: the upload/storage/summary pipeline is real and
// tested; wiring in a speech-to-text provider is a clean drop-in later
// (call it here, store the result in the same `transcript` column).
router.post('/', upload.single('file'), (req, res) => {
  const tid = tenantId(req);
  const { lead_id, recorded_by } = req.body;

  if (!req.file) return res.status(400).json({ error: 'file is required (audio)' });
  if (!lead_id) {
    fs.unlinkSync(req.file.path);
    return res.status(400).json({ error: 'lead_id is required' });
  }
  const lead = db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) {
    fs.unlinkSync(req.file.path);
    return res.status(404).json({ error: 'Lead not found for this tenant' });
  }

  const id = randomUUID();
  db.prepare(`
    INSERT INTO voice_notes (id, tenant_id, lead_id, file_name, stored_path, recorded_by)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, req.file.originalname, req.file.filename, recorded_by || null);

  res.status(201).json(db.prepare('SELECT * FROM voice_notes WHERE id = ?').get(id));
});

// GET /voice-notes?lead_id=xxx
router.get('/', (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  const rows = lead_id
    ? db.prepare('SELECT * FROM voice_notes WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC').all(tid, lead_id)
    : db.prepare('SELECT * FROM voice_notes WHERE tenant_id = ? ORDER BY created_at DESC').all(tid);
  res.json(rows);
});

// PATCH /voice-notes/:id  { transcript }
// Attach a transcript (typed manually, or from a transcription service
// once configured) — this unlocks AI Meeting Summary below.
router.patch('/:id', (req, res) => {
  const tid = tenantId(req);
  const existing = db.prepare('SELECT * FROM voice_notes WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Voice note not found' });
  if (req.body.transcript === undefined) return res.status(400).json({ error: 'transcript is required' });

  db.prepare('UPDATE voice_notes SET transcript = ? WHERE tenant_id = ? AND id = ?')
    .run(req.body.transcript, tid, req.params.id);
  res.json(db.prepare('SELECT * FROM voice_notes WHERE id = ?').get(req.params.id));
});

// POST /voice-notes/:id/summarize — AI Meeting Summary via Claude,
// run over the attached transcript (needs ANTHROPIC_API_KEY, same as
// AI Analysis).
router.post('/:id/summarize', async (req, res) => {
  const tid = tenantId(req);
  const note = db.prepare('SELECT * FROM voice_notes WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!note) return res.status(404).json({ error: 'Voice note not found' });
  if (!note.transcript) return res.status(400).json({ error: 'No transcript attached yet — use PATCH to add one first' });

  try {
    const summary = await generateText(
      `Summarize this counseling call transcript in 3-4 sentences, then list any action items as a short bullet list.\n\nTranscript:\n${note.transcript}`,
      { maxTokens: 400 },
    );
    db.prepare('UPDATE voice_notes SET ai_summary = ? WHERE id = ?').run(summary, note.id);
    res.json({ ai_summary: summary });
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

module.exports = router;
