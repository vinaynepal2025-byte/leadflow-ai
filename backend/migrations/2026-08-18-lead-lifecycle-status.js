// Migration: 2026-08-18 — Lead Lifecycle State Machine (Leads Ecosystem
// redesign, Phase 2 / Domain Model).
//
// Per LEADS_AUTOMATION_AUDIT.md section 2: `leads.stage` is unenforced
// free text, only loosely matched against a separate tenant-editable
// `pipeline_stages` table. This migration does NOT touch either of
// those -- it adds a new, separate, enum-enforced `lifecycle_status`
// column the new state machine (backend/services/leadLifecycle.js)
// actually governs, and backfills it from each lead's current `stage`
// value so every existing lead starts somewhere sensible instead of
// NULL. `stage`/`pipeline_stages` keep working exactly as before; the
// mobile app's existing stage-filter UI is untouched.
//
// Idempotent, matches the established migration pattern: ADD COLUMN IF
// NOT EXISTS, and the backfill UPDATE only touches rows where
// lifecycle_status IS NULL, so re-running this script after some leads
// already have a real (non-backfilled) status is a safe no-op for them.
//
// Run with: node migrations/2026-08-18-lead-lifecycle-status.js

require('dotenv').config();
const { Pool } = require('pg');
const { ALL_STATUSES, STAGE_BACKFILL_MAP, NEEDS_REVIEW } = require('../services/leadLifecycle');

const pool = new Pool({
  host: process.env.PGHOST,
  port: process.env.PGPORT,
  user: process.env.PGUSER,
  password: process.env.PGPASSWORD,
  database: process.env.PGDATABASE,
  ssl: { rejectUnauthorized: false },
});

const checkList = ALL_STATUSES.map((s) => `'${s}'`).join(', ');

const backfillCase = Object.entries(STAGE_BACKFILL_MAP)
  .map(([stage, status]) => `WHEN stage = '${stage}' THEN '${status}'`)
  .join('\n      ');

const statements = [
  `ALTER TABLE leads ADD COLUMN IF NOT EXISTS lifecycle_status TEXT`,
  // Constraint added separately (not inline on the column def) so this
  // script can be re-run safely even if a prior partial run already
  // added the column -- ADD CONSTRAINT has no IF NOT EXISTS in Postgres,
  // so this checks pg_constraint first.
  `DO $$
   BEGIN
     IF NOT EXISTS (
       SELECT 1 FROM pg_constraint WHERE conname = 'leads_lifecycle_status_check'
     ) THEN
       ALTER TABLE leads ADD CONSTRAINT leads_lifecycle_status_check
         CHECK (lifecycle_status IS NULL OR lifecycle_status IN (${checkList}));
     END IF;
   END $$`,
  `CREATE INDEX IF NOT EXISTS idx_leads_lifecycle_status ON leads(tenant_id, lifecycle_status)`,
  // Backfill: only rows with no lifecycle_status yet. Known legacy stage
  // values map per STAGE_BACKFILL_MAP; anything else (a tenant's custom
  // pipeline_stages name, NULL, empty string) lands in NEEDS_REVIEW
  // rather than a guessed mapping.
  `UPDATE leads
   SET lifecycle_status = CASE
      ${backfillCase}
      ELSE '${NEEDS_REVIEW}'
     END
   WHERE lifecycle_status IS NULL`,
  `CREATE TABLE IF NOT EXISTS lead_lifecycle_transitions (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    from_status TEXT NOT NULL,
    to_status TEXT NOT NULL,
    initiated_by TEXT NOT NULL DEFAULT 'manual',
    initiated_by_user_id TEXT,
    reason TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT lead_lifecycle_transitions_initiated_by_check
      CHECK (initiated_by IN ('manual', 'ai', 'automation', 'system'))
  )`,
  `CREATE INDEX IF NOT EXISTS idx_lead_lifecycle_transitions_lead ON lead_lifecycle_transitions(tenant_id, lead_id, created_at DESC)`,
];

(async () => {
  for (const sql of statements) {
    console.log('Running:', sql.slice(0, 90).replace(/\s+/g, ' '), '...');
    await pool.query(sql);
  }
  const { rows } = await pool.query(
    'SELECT lifecycle_status, COUNT(*) AS c FROM leads GROUP BY lifecycle_status ORDER BY c DESC'
  );
  console.log('Backfill result (leads per lifecycle_status):');
  console.table(rows);
  console.log('Done.');
  await pool.end();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
