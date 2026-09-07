// Migration: 2026-09-07 — teacher's own remark on a report card
// Idempotent, matches the established migration pattern.
// APPLIED LIVE 2026-09-07 via the supabase-primary MCP connection
// (qovaakuithekhotkrrdi) before this file was written.
//
// CONTEXT: Vinay's original spec listed "remark" as one of the fields a
// report card template should carry. `ai_narrative` already covers the
// AI-written (or deterministic-fallback) note, and `disclaimer`/`footerText`
// are template-wide fixed text -- neither lets a specific teacher write
// their own free-text remark for one specific student's card. Additive
// only: existing rows get NULL, no existing route/render path is affected.

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
  `ALTER TABLE report_cards ADD COLUMN IF NOT EXISTS teacher_remark TEXT`,
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
