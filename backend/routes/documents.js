const express = require('express');
const multer = require('multer');
const { randomUUID } = require('crypto');
const db = require('../db');
const { createNotification } = require('./notifications');
const { fireEvent } = require('../services/automationEngine');
const { uploadFile, getSignedUrl } = require('../services/supabaseStorage');

const router = express.Router();

// Migrated from multer.diskStorage to memoryStorage — files now go to
// Supabase Storage (persistent) instead of Render's local disk
// (ephemeral, wiped on every redeploy — this was a real, confirmed bug:
// previously-verified documents became permanently 404 after any
// redeploy). See services/supabaseStorage.js for the full story.
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } }); // 10MB cap

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// POST /documents  (multipart/form-data: file, lead_id, doc_type, uploaded_by)
router.post('/', upload.single('file'), async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, doc_type, uploaded_by } = req.body;
  if (!req.file) return res.status(400).json({ error: 'file is required' });
  if (!lead_id || !doc_type) {
    return res.status(400).json({ error: 'lead_id and doc_type are required' });
  }

  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) {
    return res.status(404).json({ error: 'Lead not found for this tenant' });
  }

  const id = randomUUID();
  const storagePath = `documents/${id}-${req.file.originalname}`;

  try {
    await uploadFile(req.file.buffer, storagePath, req.file.mimetype);
  } catch (err) {
    return res.status(502).json({ error: `Upload failed: ${err.message}` });
  }

  // stored_path now holds the RELATIVE storage path (not a public URL) —
  // the bucket is private as of 2026-08-08, so downloads go through
  // getSignedUrl() at request-time (see GET /:id/download below).
  await db.prepare(`
    INSERT INTO documents (id, tenant_id, lead_id, doc_type, file_name, stored_path, uploaded_by)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, doc_type, req.file.originalname, storagePath, uploaded_by || null);

  res.status(201).json(await db.prepare('SELECT * FROM documents WHERE id = ?').get(id));
});

// GET /documents?lead_id=xxx
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  const rows = lead_id
    ? await db.prepare('SELECT * FROM documents WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC').all(tid, lead_id)
    : await db.prepare('SELECT * FROM documents WHERE tenant_id = ? ORDER BY created_at DESC').all(tid);
  res.json(rows);
});

// PATCH /documents/:id  { status: 'verified' | 'rejected' }
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const { status } = req.body;
  if (!['pending', 'verified', 'rejected'].includes(status)) {
    return res.status(400).json({ error: 'status must be pending, verified, or rejected' });
  }
  const existing = await db.prepare('SELECT * FROM documents WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Document not found' });

  await db.prepare('UPDATE documents SET status = ? WHERE tenant_id = ? AND id = ?').run(status, tid, req.params.id);
  if (status === 'rejected') {
    const lead = await db.prepare('SELECT full_name FROM leads WHERE id = ?').get(existing.lead_id);
    await createNotification(tid, {
      title: `Document rejected: ${existing.doc_type}`,
      body: `${lead?.full_name || 'A lead'}'s ${existing.doc_type} needs to be re-uploaded`,
      linkType: 'lead',
      linkId: existing.lead_id,
    });
    await fireEvent('document.rejected', { tenant_id: tid, lead_id: existing.lead_id, doc_type: existing.doc_type });
  }
  res.json(await db.prepare('SELECT * FROM documents WHERE id = ?').get(req.params.id));
});

// GET /documents/:id/download
//
// Two formats can be in stored_path, depending on when the row was created:
//  - Legacy (pre 2026-08-08): a full "http..." public Supabase Storage URL,
//    from when the bucket was public-read. Still redirect straight to it —
//    it still works until/unless these rows are separately migrated.
//  - Current: a relative storage path (e.g. "documents/<id>-<name>"). The
//    bucket is private now, so we generate a short-lived signed URL
//    on-demand and redirect to that instead.
router.get('/:id/download', async (req, res) => {
  const tid = tenantId(req);
  const doc = await db.prepare('SELECT * FROM documents WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!doc) return res.status(404).json({ error: 'Document not found' });
  if (!doc.stored_path) {
    return res.status(410).json({ error: 'This file was uploaded before the storage migration and is no longer available — please re-upload it.' });
  }

  if (doc.stored_path.startsWith('http')) {
    return res.redirect(doc.stored_path);
  }

  try {
    const signedUrl = await getSignedUrl(doc.stored_path, 300);
    return res.redirect(signedUrl);
  } catch (err) {
    return res.status(502).json({ error: `Could not generate download link: ${err.message}` });
  }
});

module.exports = router;
