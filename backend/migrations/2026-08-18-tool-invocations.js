// Migration: 2026-08-18 — Tool Registry audit log (Leads Ecosystem
// redesign, Phase 3). See services/toolRegistry.js for the registry
// itself; this table is where invokeTool() unconditionally records
// every invocation -- succeeded, failed, or rejected before the handler
// even ran -- per the spec's per-tool audit-logging requirement.
//
// tenant_id has no FK constraint deliberately: a rejected invocation
// (e.g. an unknown tool name, or a missing/garbage tenant_id) must still
// be logged, and a FK would make exactly those edge cases the ones that
// fail to record.
//
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-18-tool-invocations.js

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
  `CREATE TABLE IF NOT EXISTS tool_invocations (
    id TEXT PRIMARY KEY,
    tenant_id TEXT,
    tool_name TEXT NOT NULL,
    actor_type TEXT,
    actor_id TEXT,
    input_json TEXT,
    status TEXT NOT NULL,
    result_summary TEXT,
    error_message TEXT,
    duration_ms INTEGER,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT tool_invocations_status_check CHECK (status IN ('succeeded', 'failed', 'rejected'))
  )`,
  `CREATE INDEX IF NOT EXISTS idx_tool_invocations_tenant ON tool_invocations(tenant_id, tool_name, created_at DESC)`,
];

(async () => {
  for (const sql of statements) {
    console.log('Running:', sql.slice(0, 90).replace(/\s+/g, ' '), '...');
    await pool.query(sql);
  }
  console.log('Done.');
  await pool.end();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
