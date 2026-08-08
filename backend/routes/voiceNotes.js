const express = require('express');
const multer = require('multer');
const { randomUUID } = require('crypto');
const db = require('../db');
const { generateText } = require('../services/aiProvider');
const { uploadFile, getSignedUrl } = require('../services/supabaseStorage');

const router = express.Router();

// Migrated from multer.diskStorage to memoryStorage — see documents.js
// and services/supabaseStorage.js for the full story (Render's local
// disk is ephemeral and was silently losing every uploaded file on
// every redeploy — confirmed live this session).
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 25 * 1024 * 1024 } });

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
router.post('/', upload.single('file'), async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, recorded_by } = req.body;

  if (!req.file) return res.status(400).json({ error: 'file is required (audio)' });
  if (!lead_id) {
    return res.status(400).json({ error: 'lead_id is required' });
  }
  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) {
    return res.status(404).json({ error: 'Lead not found for this tenant' });
  }

  const id = randomUUID();
  const storagePath = `voice-notes/${id}-${req.file.originalname}`;

  try {
    await uploadFile(req.file.buffer, storagePath, req.file.mimetype);
  } catch (err) {
    return res.status(502).json({ error: `Upload failed: ${err.message}` });
  }

  // stored_path holds the RELATIVE storage path (not a public URL) —
  // the bucket is private, so downloads go through getSignedUrl() at
  // request-time (see GET /:id/download below). Same fix as documents.js.
  await db.prepare(`
    INSERT INTO voice_notes (id, tenant_id, lead_id, file_name, stored_path, recorded_by)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, req.file.originalname, storagePath, recorded_by || null);

  res.status(201).json(await db.prepare('SELECT * FROM voice_notes WHERE id = ?').get(id));
});

// GET /voice-notes?lead_id=xxx
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  const rows = lead_id
    ? await db.prepare('SELECT * FROM voice_notes WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC').all(tid, lead_id)
    : await db.prepare('SELECT * FROM voice_notes WHERE tenant_id = ? ORDER BY created_at DESC').all(tid);
  res.json(rows);
});

// PATCH /voice-notes/:id  { transcript }
// Attach a transcript (typed manually, or from a transcription service
// once configured) — this unlocks AI Meeting Summary below.
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT * FROM voice_notes WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Voice note not found' });
  if (req.body.transcript === undefined) return res.status(400).json({ error: 'transcript is required' });

  await db.prepare('UPDATE voice_notes SET transcript = ? WHERE tenant_id = ? AND id = ?')
    .run(req.body.transcript, tid, req.params.id);
  res.json(await db.prepare('SELECT * FROM voice_notes WHERE id = ?').get(req.params.id));
});

// POST /voice-notes/:id/summarize — AI Meeting Summary via Claude,
// run over the attached transcript (needs ANTHROPIC_API_KEY, same as
// AI Analysis).
router.post('/:id/summarize', async (req, res) => {
  const tid = tenantId(req);
  const note = await db.prepare('SELECT * FROM voice_notes WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!note) return res.status(404).json({ error: 'Voice note not found' });
  if (!note.transcript) return res.status(400).json({ error: 'No transcript attached yet — use PATCH to add one first' });

  try {
    const summary = await generateText(
      `Summarize this counseling call transcript in 3-4 sentences, then list any action items as a short bullet list.\n\nTranscript:\n${note.transcript}`,
      { maxTokens: 400 },
    );
    await db.prepare('UPDATE voice_notes SET ai_summary = ? WHERE id = ?').run(summary, note.id);
    res.json({ ai_summary: summary });
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// GET /voice-notes/:id/download
//
// Two formats can be in stored_path, same as documents.js:
//  - Legacy: a full "http..." public Supabase Storage URL. Redirect
//    straight to it (works only if the referenced object still allows
//    public access — pre-2026-08-08 rows may 400, see migration note).
//  - Current: a relative storage path. Generate a short-lived signed
//    URL on-demand and redirect to that instead.
router.get('/:id/download', async (req, res) => {
  const tid = tenantId(req);
  const note = await db.prepare('SELECT * FROM voice_notes WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!note) return res.status(404).json({ error: 'Voice note not found' });
  if (!note.stored_path) {
    return res.status(410).json({ error: 'This recording was made before the storage migration and is no longer available — please record a new one.' });
  }

  if (note.stored_path.startsWith('http')) {
    return res.redirect(note.stored_path);
  }

  try {
    const signedUrl = await getSignedUrl(note.stored_path, 300);
    return res.redirect(signedUrl);
  } catch (err) {
    return res.status(502).json({ error: `Could not generate download link: ${err.message}` });
  }
});

module.exports = router;
