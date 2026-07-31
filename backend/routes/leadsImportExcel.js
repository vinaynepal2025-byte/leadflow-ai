const express = require('express');
const multer = require('multer');
const readXlsxFile = require('read-excel-file/node');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// POST /leads/import-excel  (multipart/form-data: file=<xlsx>)
// First row must be a header row with column names matching the CSV
// import's expected columns (full_name, phone, email, source, notes) —
// case-insensitive, any order. Same duplicate-by-phone skip logic as CSV
// import, so behavior is consistent across import methods.
router.post('/', upload.single('file'), async (req, res) => {
  const tid = tenantId(req);
  if (!req.file) return res.status(400).json({ error: 'file is required (.xlsx)' });

  let rows;
  try {
    const parsed = await readXlsxFile(req.file.buffer);
    // This version of read-excel-file returns [{ sheet, data }, ...] rather
    // than a flat row array — use the first sheet's data either way.
    rows = Array.isArray(parsed) && parsed.length > 0 && parsed[0] && parsed[0].data
      ? parsed[0].data
      : parsed;
  } catch (err) {
    return res.status(400).json({ error: `Could not parse Excel file: ${err.message}` });
  }
  if (rows.length < 2) {
    return res.status(400).json({ error: 'File must have a header row plus at least one data row' });
  }

  const header = rows[0].map((h) => String(h || '').toLowerCase().trim());
  const colIndex = (names) => names.map((n) => header.indexOf(n)).find((i) => i !== -1);
  const nameCol = colIndex(['full_name', 'name']);
  const phoneCol = colIndex(['phone', 'phone number']);
  const emailCol = colIndex(['email']);
  const sourceCol = colIndex(['source']);
  const notesCol = colIndex(['notes']);

  const results = { created: 0, skipped_duplicate: 0, skipped_invalid: 0, errors: [] };

  for (let i = 1; i < rows.length; i++) {
    const row = rows[i];
    const fullName = nameCol !== undefined ? row[nameCol] : null;
    const phone = phoneCol !== undefined && row[phoneCol] ? String(row[phoneCol]) : null;
    const email = emailCol !== undefined ? row[emailCol] : null;
    const source = (sourceCol !== undefined && row[sourceCol]) || 'Excel Import';
    const notes = notesCol !== undefined ? row[notesCol] : null;

    if (!fullName) {
      results.skipped_invalid++;
      results.errors.push(`Row ${i + 1}: missing full_name`);
      continue;
    }

    if (phone) {
      const dup = db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND phone = ?').get(tid, phone);
      if (dup) {
        results.skipped_duplicate++;
        continue;
      }
    }

    const id = randomUUID();
    db.prepare(`
      INSERT INTO leads (id, tenant_id, full_name, phone, email, source, notes)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(id, tid, String(fullName), phone, email ? String(email) : null, String(source), notes ? String(notes) : null);
    results.created++;
  }

  res.status(201).json(results);
});

module.exports = router;
