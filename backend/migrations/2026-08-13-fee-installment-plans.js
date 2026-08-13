// Migration: 2026-08-13 — Fee installment plans (Phase 2)
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-13-fee-installment-plans.js
//
// Note: already applied directly to the live Supabase DB via MCP during
// this session. This file exists so the schema history is reproducible
// from a fresh environment (e.g. a new dev DB) — running it again is a
// no-op thanks to IF NOT EXISTS.

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
  `ALTER TABLE fee_payments ADD COLUMN IF NOT EXISTS plan_id TEXT`,
  // groups installments created together by POST /fees/plan; NULL for
  // one-off fee records (fully backward compatible)
  `ALTER TABLE fee_payments ADD COLUMN IF NOT EXISTS installment_number INTEGER`,
  `ALTER TABLE fee_payments ADD COLUMN IF NOT EXISTS total_installments INTEGER`,
  `CREATE INDEX IF NOT EXISTS idx_fee_payments_plan ON fee_payments(plan_id)`,
];

(async () => {
  for (const sql of statements) {
    console.log('Running:', sql.slice(0, 80), '...');
    await pool.query(sql);
  }
  console.log('Done.');
  await pool.end();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
