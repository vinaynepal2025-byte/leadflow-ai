// Migration: 2026-08-13 — Documents expiry + consent form templates (Phase 4)
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-13-documents-compliance-hardening.js
//
// Note: schema + demo-consultancy default consent language already applied
// directly to the live Supabase DB via MCP during this session.

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
  `ALTER TABLE documents ADD COLUMN IF NOT EXISTS expiry_date TEXT`,
  `CREATE TABLE IF NOT EXISTS consent_form_templates (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    consent_type TEXT NOT NULL,
    title TEXT NOT NULL,
    body_text TEXT NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    UNIQUE(tenant_id, consent_type)
  )`,
];

(async () => {
  for (const sql of statements) {
    console.log('Running:', sql.slice(0, 80), '...');
    await pool.query(sql);
  }
  console.log('Done. (Default DPDP-aligned consent language for demo-consultancy was seeded separately — see Notion Config page to replicate for a new tenant.)');
  await pool.end();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
