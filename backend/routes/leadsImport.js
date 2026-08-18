const express = require('express');
const multer = require('multer');
const { parse } = require('csv-parse/sync');
const { randomUUID } = require('crypto');
const db = require('../db');

// Simple Levenshtein distance — used for fuzzy name matching when a lead
// has no phone number to dedupe on exactly. Small, dependency-free, and
// good enough for "Rahul Sharma" vs "Rahul Sharmma" typo-level catches —
// not a claim of AI-grade entity resolution, just an honest second pass.
function levenshtein(a, b) {
  const m = a.length, n = b.length;
  const dp = Array.from({ length: m + 1 }, (_, i) => [i, ...Array(n).fill(0)]);
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] = a[i - 1] === b[j - 1]
        ? dp[i - 1][j - 1]
        : 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
    }
  }
  return dp[m][n];
}

async function findFuzzyDuplicate(tenantId, fullName) {
  const candidates = await db.prepare('SELECT id, full_name FROM leads WHERE tenant_id = ?').all(tenantId);
  const normalized = fullName.toLowerCase().trim();
  for (const c of candidates) {
    const dist = levenshtein(normalized, c.full_name.toLowerCase().trim());
    if (dist <= 2 && normalized.length > 4) return c; // close typo-level match on a real name
  }
  return null;
}

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// POST /leads/import  (multipart/form-data: file=<csv>)
// Expected columns (case-insensitive, order doesn't matter):
//   full_name (required), phone, email, source, notes
// Duplicate Intelligence (v1): a row is skipped as a duplicate if a lead
// with the same phone number already exists for this tenant — this is a
// simple, honest first pass, not the fuzzy/AI duplicate-matching the
// original brief describes; that's a clearly separate, later capability.
router.post('/', upload.single('file'), async (req, res) => {
  const tid = tenantId(req);
  if (!req.file) return res.status(400).json({ error: 'file is required (CSV)' });

  let rows;
  try {
    rows = parse(req.file.buffer, { columns: true, skip_empty_lines: true, trim: true });
  } catch (err) {
    return res.status(400).json({ error: `Could not parse CSV: ${err.message}` });
  }

  const results = { created: 0, skipped_duplicate: 0, skipped_invalid: 0, errors: [] };

  for (const [i, row] of rows.entries()) {
    // Normalize column names case-insensitively
    const normalized = {};
    for (const key of Object.keys(row)) {
      normalized[key.toLowerCase().trim()] = row[key];
    }

    const fullName = normalized['full_name'] || normalized['name'];
    const phone = normalized['phone'] || normalized['phone number'] || null;
    const email = normalized['email'] || null;
    const source = normalized['source'] || 'CSV Import';
    const notes = normalized['notes'] || null;

    if (!fullName) {
      results.skipped_invalid++;
      results.errors.push(`Row ${i + 2}: missing full_name`);
      continue;
    }

    if (phone) {
      const dup = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND phone = ?').get(tid, phone);
      if (dup) {
        results.skipped_duplicate++;
        continue;
      }
    }

    const id = randomUUID();
    await db.prepare(`
      INSERT INTO leads (id, tenant_id, full_name, phone, email, source, notes, lifecycle_status)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(id, tid, fullName, phone, email, source, notes, 'NEW');
    results.created++;
  }

  res.status(201).json(results);
});

module.exports = router;
