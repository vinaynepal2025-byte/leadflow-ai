// backend/routes/leadsExcelV2.js
// Phase 2 — Customizable-column Excel/CSV import + export.
//
// Deliberately a NEW, self-contained file rather than editing the existing
// leadsImportExcel.js — that file's fixed-column behavior stays as a
// simple fallback, and this file adds the column-mapping + export
// capability without risking a blind patch on code this session hadn't
// freshly verified against the live repo.
//
// Export is plain CSV, not a binary .xlsx — deliberate choice: it opens
// natively in Excel/Google Sheets/Sheets app, needs zero new npm
// dependency (no xlsx-writer library, so no new security surface), and
// keeps this "investment-free" per the standing project constraint.
//
// Import flow is two-step (stateless, no server-side session):
//   1. POST /leads-excel/import/preview  -> headers + sample rows + a
//      best-guess mapping, so the mobile app can render a mapping screen.
//   2. POST /leads-excel/import/commit   -> same file re-uploaded, plus
//      the counselor-confirmed mapping -> actually creates leads.

const express = require('express');
const multer = require('multer');
const readXlsxFile = require('read-excel-file/node');
const { parse: parseCsv } = require('csv-parse/sync');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });

function tenantId(req) {
  // Query-param fallback exists specifically for /export: that link opens
  // in the device's browser (so Android's own download manager saves the
  // file, no new Flutter package needed) — a browser navigation can't set
  // custom headers, so ?tenant_id= is how it identifies the tenant there.
  return req.header('x-tenant-id') || req.query.tenant_id || 'demo-consultancy';
}

// Standard lead fields a column can be mapped to. Anything else the
// counselor maps becomes a custom field (stored in leads.custom_fields).
const STANDARD_TARGETS = ['full_name', 'phone', 'email', 'source', 'notes', 'stage', 'parent_name', 'parent_phone'];

async function parseUploadedFile(file) {
  const isExcel = file.originalname.toLowerCase().endsWith('.xlsx');
  if (isExcel) {
    const parsed = await readXlsxFile(file.buffer);
    const rows = Array.isArray(parsed) && parsed.length > 0 && parsed[0] && parsed[0].data
      ? parsed[0].data
      : parsed;
    return rows.map((row) => row.map((cell) => (cell === null || cell === undefined ? '' : String(cell))));
  }
  // CSV
  const records = parseCsv(file.buffer, { skip_empty_lines: true, trim: true });
  return records; // array of arrays, first row = header
}

function guessMapping(headers) {
  const guess = {};
  const lower = headers.map((h) => h.toLowerCase().trim());
  const tryMatch = (patterns, target) => {
    const idx = lower.findIndex((h) => patterns.includes(h));
    if (idx !== -1) guess[headers[idx]] = target;
  };
  tryMatch(['full_name', 'name', 'student name', 'lead name'], 'full_name');
  tryMatch(['phone', 'phone number', 'mobile', 'contact number'], 'phone');
  tryMatch(['email', 'email address'], 'email');
  tryMatch(['source', 'lead source'], 'source');
  tryMatch(['notes', 'note', 'remarks'], 'notes');
  tryMatch(['stage', 'status'], 'stage');
  tryMatch(['parent name', 'parent_name', 'guardian name'], 'parent_name');
  tryMatch(['parent phone', 'parent_phone', 'guardian phone'], 'parent_phone');
  return guess;
}

// ---------------------------------------------------------------------
// POST /leads-excel/import/preview
// ---------------------------------------------------------------------
router.post('/import/preview', upload.single('file'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'file is required (.xlsx or .csv)' });

  let rows;
  try {
    rows = await parseUploadedFile(req.file);
  } catch (err) {
    return res.status(400).json({ error: `Could not parse file: ${err.message}` });
  }
  if (rows.length < 2) {
    return res.status(400).json({ error: 'File must have a header row plus at least one data row' });
  }

  const headers = rows[0].map((h) => String(h || '').trim()).filter((h) => h.length > 0);
  const sampleRows = rows.slice(1, 4); // first 3 data rows, for the mapping preview screen

  res.json({
    headers,
    sample_rows: sampleRows,
    total_data_rows: rows.length - 1,
    suggested_mapping: guessMapping(headers),
    standard_targets: STANDARD_TARGETS,
  });
});

// ---------------------------------------------------------------------
// POST /leads-excel/import/commit
// multipart fields: file=<xlsx|csv>, mapping=<JSON string>
// mapping shape: { "<header text>": "full_name" | "phone" | ... | "custom:ielts_score" }
// A header omitted from mapping is simply ignored.
// ---------------------------------------------------------------------
router.post('/import/commit', upload.single('file'), async (req, res) => {
  const tid = tenantId(req);
  if (!req.file) return res.status(400).json({ error: 'file is required (.xlsx or .csv)' });

  let mapping;
  try {
    mapping = JSON.parse(req.body.mapping || '{}');
  } catch {
    return res.status(400).json({ error: 'mapping must be a valid JSON string' });
  }
  if (!Object.values(mapping).includes('full_name')) {
    return res.status(400).json({ error: 'At least one column must be mapped to full_name' });
  }

  let rows;
  try {
    rows = await parseUploadedFile(req.file);
  } catch (err) {
    return res.status(400).json({ error: `Could not parse file: ${err.message}` });
  }
  if (rows.length < 2) {
    return res.status(400).json({ error: 'File must have a header row plus at least one data row' });
  }

  const headers = rows[0].map((h) => String(h || '').trim());
  const results = { created: 0, skipped_duplicate: 0, skipped_invalid: 0, errors: [] };

  for (let i = 1; i < rows.length; i++) {
    const row = rows[i];
    const record = { custom_fields: {} };

    for (const [header, target] of Object.entries(mapping)) {
      const colIdx = headers.indexOf(header);
      if (colIdx === -1) continue;
      const value = row[colIdx] === undefined || row[colIdx] === null ? '' : String(row[colIdx]).trim();
      if (!value) continue;

      if (target.startsWith('custom:')) {
        record.custom_fields[target.slice(7)] = value;
      } else if (STANDARD_TARGETS.includes(target)) {
        record[target] = value;
      }
    }

    if (!record.full_name) {
      results.skipped_invalid++;
      results.errors.push(`Row ${i + 1}: missing full_name`);
      continue;
    }

    if (record.phone) {
      const dup = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND phone = ?').get(tid, record.phone);
      if (dup) {
        results.skipped_duplicate++;
        continue;
      }
    }

    const id = randomUUID();
    await db.prepare(`
      INSERT INTO leads (id, tenant_id, full_name, phone, email, source, notes, stage, parent_name, parent_phone, custom_fields)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      id, tid, record.full_name, record.phone || null, record.email || null,
      record.source || 'Excel Import', record.notes || null, record.stage || 'New',
      record.parent_name || null, record.parent_phone || null,
      Object.keys(record.custom_fields).length > 0 ? JSON.stringify(record.custom_fields) : null,
    );
    results.created++;
  }

  res.status(201).json(results);
});

// ---------------------------------------------------------------------
// GET /leads-excel/export?columns=full_name,phone,email,stage,source,notes,custom:ielts_score
// Returns a downloadable CSV. If ?columns is omitted, a sensible default
// set is used. Column order in the query string is preserved in the file.
// ---------------------------------------------------------------------
function csvEscape(value) {
  const str = value === null || value === undefined ? '' : String(value);
  if (str.includes(',') || str.includes('"') || str.includes('\n')) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

router.get('/export', async (req, res) => {
  const tid = tenantId(req);
  const requested = (req.query.columns || 'full_name,phone,email,source,stage,notes,created_at')
    .split(',').map((c) => c.trim()).filter(Boolean);

  const leads = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? ORDER BY created_at DESC').all(tid);

  const headerLabels = requested.map((c) => (c.startsWith('custom:') ? c.slice(7) : c));
  const lines = [headerLabels.map(csvEscape).join(',')];

  for (const lead of leads) {
    let customFields = {};
    if (lead.custom_fields) {
      try {
        customFields = typeof lead.custom_fields === 'string' ? JSON.parse(lead.custom_fields) : lead.custom_fields;
      } catch { /* malformed custom_fields on this row — export blank instead of crashing the whole file */ }
    }
    const row = requested.map((col) => {
      if (col.startsWith('custom:')) return customFields[col.slice(7)] ?? '';
      return lead[col] ?? '';
    });
    lines.push(row.map(csvEscape).join(','));
  }

  const csv = lines.join('\r\n');
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="leads-export-${Date.now()}.csv"`);
  res.send(csv);
});

module.exports = router;
