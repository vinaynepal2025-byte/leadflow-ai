// Migration: 2026-08-18 — automation_mode (Leads Ecosystem redesign,
// Phase 6: MANUAL/AUTO mode toggle).
//
// Every tenant defaults to 'manual' -- the safe, current behavior
// (agents only ever act when a human clicks a button in the app).
// Flipping a tenant to 'auto' is the one thing in this whole redesign
// that lets agents enqueue actions without a human in the loop per
// action; see services/agentScheduler.js for exactly what that does and
// doesn't mean.
//
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-18-automation-mode.js

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
  `ALTER TABLE tenants ADD COLUMN IF NOT EXISTS automation_mode TEXT NOT NULL DEFAULT 'manual'`,
  `DO $$
   BEGIN
     IF NOT EXISTS (
       SELECT 1 FROM pg_constraint WHERE conname = 'tenants_automation_mode_check'
     ) THEN
       ALTER TABLE tenants ADD CONSTRAINT tenants_automation_mode_check
         CHECK (automation_mode IN ('manual', 'auto'));
     END IF;
   END $$`,
];

(async () => {
  for (const sql of statements) {
    console.log('Running:', sql.slice(0, 90).replace(/\s+/g, ' '), '...');
    await pool.query(sql);
  }
  const { rows } = await pool.query('SELECT id, automation_mode FROM tenants ORDER BY id');
  console.log('Tenants after migration:');
  console.table(rows);
  console.log('Done.');
  await pool.end();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
