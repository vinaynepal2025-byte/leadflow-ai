// Migration: 2026-09-07 — separate father/mother contacts on leads
// Idempotent, matches the established migration pattern (see
// 2026-09-06-exam-intelligence-report-cards.js).
// Run with: node migrations/2026-09-07-lead-father-mother-contacts.js
//
// APPLIED LIVE 2026-09-07 via the supabase-primary MCP connection
// (qovaakuithekhotkrrdi) before this file was written — this is the repo
// record, not a pending change.
//
// CONTEXT: `leads` only had a single parent_name/parent_phone/parent_relation
// (one guardian). The Exam Intelligence report-card feature needs a separate
// WhatsApp hyperlink button for father AND mother — real college marks
// sheets already carry "Father's Name"/"Cell Number"/"Mother's Name"/
// "Cell Number" columns (examIntelligence.js's parser previously recognized
// but deliberately ignored them). Additive only: existing parent_name/
// parent_phone/parent_relation are untouched and keep working everywhere
// they're already used; these four columns default to NULL, so no existing
// row or route is affected.

require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.PGHOST,
  port: process.env.PGPORT,
  user: process.env.PGUSER,
  password: process.env.PGPASSWORD,
  database: process.env.PGDATABASE,
  ssl: { rejectUnauthorized: false },
});

const statements = [
  `ALTER TABLE leads ADD COLUMN IF NOT EXISTS father_name TEXT`,
  `ALTER TABLE leads ADD COLUMN IF NOT EXISTS father_phone TEXT`,
  `ALTER TABLE leads ADD COLUMN IF NOT EXISTS mother_name TEXT`,
  `ALTER TABLE leads ADD COLUMN IF NOT EXISTS mother_phone TEXT`,
];

(async () => {
  for (const sql of statements) {
    console.log('Running:', sql.slice(0, 80).replace(/\s+/g, ' '), '...');
    await pool.query(sql);
  }
  console.log('Done.');
  await pool.end();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
