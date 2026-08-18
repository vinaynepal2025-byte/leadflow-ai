// Migration: 2026-08-18 — Durable Orchestrator job queue (Leads
// Ecosystem redesign, Phase 4). See services/orchestrator.js for the
// full rationale: this is a new, separate queue for the Tool Registry
// (Phase 3) that the AI agent framework (Phase 5) will enqueue into --
// it does not touch or replace the existing automation_rules table or
// automationEngine.js's fireEvent(), which keep working exactly as
// before.
//
// idempotency_key's uniqueness is a partial unique index (only when the
// key is actually provided) rather than a plain UNIQUE column, since
// most jobs won't have one and NULL != NULL in a normal unique
// constraint would make that a non-issue anyway -- the partial index is
// just the more explicit, self-documenting way to say "only leads
// enqueued with a real dedupe key are deduped."
//
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-18-automation-jobs.js

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
  `CREATE TABLE IF NOT EXISTS automation_jobs (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    event TEXT,
    tool_name TEXT NOT NULL,
    tool_input_json TEXT NOT NULL,
    idempotency_key TEXT,
    initiated_by TEXT NOT NULL DEFAULT 'automation',
    initiated_by_id TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 5,
    next_attempt_at TIMESTAMP NOT NULL DEFAULT now(),
    last_error TEXT,
    result_json TEXT,
    requires_approval BOOLEAN NOT NULL DEFAULT false,
    approved_by TEXT,
    approved_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT automation_jobs_status_check
      CHECK (status IN ('pending', 'running', 'succeeded', 'failed', 'dead_letter', 'awaiting_approval', 'cancelled')),
    CONSTRAINT automation_jobs_initiated_by_check
      CHECK (initiated_by IN ('manual', 'ai', 'automation', 'system'))
  )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS idx_automation_jobs_idempotency
     ON automation_jobs(tenant_id, idempotency_key) WHERE idempotency_key IS NOT NULL`,
  `CREATE INDEX IF NOT EXISTS idx_automation_jobs_due ON automation_jobs(status, next_attempt_at)`,
  `CREATE INDEX IF NOT EXISTS idx_automation_jobs_tenant ON automation_jobs(tenant_id, created_at DESC)`,
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
