const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { randomUUID } = require('crypto');
const db = require('../db');
const { createNotification } = require('./notifications');
const { fireEvent } = require('../services/automationEngine');

const router = express.Router();

const UPLOAD_DIR = path.join(__dirname, '..', 'uploads');
if (!fs.existsSync(UPLOAD_DIR)) fs.mkdirSync(UPLOAD_DIR, { recursive: true });

// Note: local disk storage for v1/development only. Production target per
// VertiCore's TSE-08 baseline is Ceph/Garage (S3-compatible object storage) —
// swapping the storage engine here is the only change needed later; the
// API shape (upload/list/verify/download) stays the same.
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, UPLOAD_DIR),
  filename: (req, file, cb) => cb(null, `${randomUUID()}-${file.originalname}`),
});
const upload = multer({ storage, limits: { fileSize: 10 * 1024 * 1024 } }); // 10MB cap

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// POST /documents  (multipart/form-data: file, lead_id, doc_type, uploaded_by)
router.post('/', upload.single('file'), (req, res) => {
  const tid = tenantId(req);
  const { lead_id, doc_type, uploaded_by } = req.body;

  if (!req.file) return res.status(400).json({ error: 'file is required' });
  if (!lead_id || !doc_type) {
    fs.unlinkSync(req.file.path); // clean up orphaned upload
    return res.status(400).json({ error: 'lead_id and doc_type are required' });
  }

  const lead = db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) {
    fs.unlinkSync(req.file.path);
    return res.status(404).json({ error: 'Lead not found for this tenant' });
  }

  const id = randomUUID();
  db.prepare(`
    INSERT INTO documents (id, tenant_id, lead_id, doc_type, file_name, stored_path, uploaded_by)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, doc_type, req.file.originalname, req.file.filename, uploaded_by || null);

  res.status(201).json(db.prepare('SELECT * FROM documents WHERE id = ?').get(id));
});

// GET /documents?lead_id=xxx
router.get('/', (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  const rows = lead_id
    ? db.prepare('SELECT * FROM documents WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC').all(tid, lead_id)
    : db.prepare('SELECT * FROM documents WHERE tenant_id = ? ORDER BY created_at DESC').all(tid);
  res.json(rows);
});

// PATCH /documents/:id  { status: 'verified' | 'rejected' }
router.patch('/:id', (req, res) => {
  const tid = tenantId(req);
  const { status } = req.body;
  if (!['pending', 'verified', 'rejected'].includes(status)) {
    return res.status(400).json({ error: 'status must be pending, verified, or rejected' });
  }
  const existing = db.prepare('SELECT * FROM documents WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Document not found' });

  db.prepare('UPDATE documents SET status = ? WHERE tenant_id = ? AND id = ?').run(status, tid, req.params.id);
  if (status === 'rejected') {
    const lead = db.prepare('SELECT full_name FROM leads WHERE id = ?').get(existing.lead_id);
    createNotification(tid, {
      title: `Document rejected: ${existing.doc_type}`,
      body: `${lead?.full_name || 'A lead'}'s ${existing.doc_type} needs to be re-uploaded`,
      linkType: 'lead',
      linkId: existing.lead_id,
    });
    fireEvent('document.rejected', { tenant_id: tid, lead_id: existing.lead_id, doc_type: existing.doc_type });
  }
  res.json(db.prepare('SELECT * FROM documents WHERE id = ?').get(req.params.id));
});

// GET /documents/:id/download
router.get('/:id/download', (req, res) => {
  const tid = tenantId(req);
  const doc = db.prepare('SELECT * FROM documents WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!doc) return res.status(404).json({ error: 'Document not found' });
  res.download(path.join(UPLOAD_DIR, doc.stored_path), doc.file_name);
});

module.exports = router;
