// Migration: 2026-08-05 — Calling Cockpit Phase 1
// Idempotent (safe to re-run) — matches the pattern established in
// 2026-08-03-peer-review-per-minute-pricing.js
//
// Run with: node migrations/2026-08-05-calling-cockpit-phase1.js
// (loads .env itself, uses the same pg Pool config as db.js)

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
  // --- leads: source categorization (subfolder-style filtering) ---
  `ALTER TABLE leads ADD COLUMN IF NOT EXISTS source_category TEXT DEFAULT 'direct'`,
  // saved_contact | company_forwarded | direct | scraped | social | referral

  `ALTER TABLE leads ADD COLUMN IF NOT EXISTS last_contacted_at TIMESTAMP`,
  `ALTER TABLE leads ADD COLUMN IF NOT EXISTS engagement_trend TEXT DEFAULT 'unknown'`,
  // unknown | rising | steady | cooling | cold — updated by scoring/analysis pass

  `CREATE INDEX IF NOT EXISTS idx_leads_source_category ON leads(tenant_id, source_category)`,

  // --- offers: what was promised, how much, when, by whom ---
  `CREATE TABLE IF NOT EXISTS offers (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    offer_text TEXT NOT NULL,
    amount NUMERIC,
    currency TEXT DEFAULT 'INR',
    given_by TEXT,
    given_at TIMESTAMP NOT NULL DEFAULT now(),
    valid_until TIMESTAMP,
    status TEXT NOT NULL DEFAULT 'active',
    -- active | accepted | expired | withdrawn
    notes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT now()
  )`,
  `CREATE INDEX IF NOT EXISTS idx_offers_lead ON offers(tenant_id, lead_id)`,

  // --- content_library: reusable flyers/links/PDFs/messages, tagged for
  // the draft engine to pick from (per-lead personalization, not blast) ---
  `CREATE TABLE IF NOT EXISTS content_library (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    title TEXT NOT NULL,
    content_type TEXT NOT NULL,
    -- flyer_image | pdf | link | text_snippet | video
    file_url TEXT,
    link_url TEXT,
    body_text TEXT,
    tags TEXT,
    -- JSON array: ["mbbs", "georgia", "fee-structure", "stage:negotiation"]
    language TEXT DEFAULT 'en',
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT now()
  )`,
  `CREATE INDEX IF NOT EXISTS idx_content_library_tenant ON content_library(tenant_id, active)`,

  // --- content_sends: log of exactly what was sent to which lead, when —
  // this is what prevents duplicate-content sends and feeds win-pattern
  // replication later (Phase 3) ---
  `CREATE TABLE IF NOT EXISTS content_sends (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    content_id TEXT REFERENCES content_library(id),
    channel TEXT NOT NULL,
    -- whatsapp | email | call
    draft_text TEXT,
    sent_at TIMESTAMP NOT NULL DEFAULT now(),
    sent_by TEXT
  )`,
  `CREATE INDEX IF NOT EXISTS idx_content_sends_lead ON content_sends(tenant_id, lead_id)`,
];

(async () => {
  const client = await pool.connect();
  try {
    for (const sql of statements) {
      await client.query(sql);
      console.log('OK:', sql.split('\n')[0].slice(0, 70));
    }
    console.log('\n✅ Calling Cockpit Phase 1 migration complete.');
  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
})();
