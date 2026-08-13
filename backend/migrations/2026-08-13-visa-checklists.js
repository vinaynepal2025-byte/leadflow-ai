// Migration: 2026-08-13 — Visa document checklists (Phase 3)
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-13-visa-checklists.js
//
// Note: table creation + default seed for demo-consultancy already applied
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
  `CREATE TABLE IF NOT EXISTS visa_checklist_items (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    country TEXT NOT NULL,
    visa_type TEXT NOT NULL DEFAULT 'Student',
    doc_type TEXT NOT NULL,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT now()
  )`,
  `CREATE INDEX IF NOT EXISTS idx_visa_checklist_tenant_country ON visa_checklist_items(tenant_id, country, visa_type)`,
];

(async () => {
  for (const sql of statements) {
    console.log('Running:', sql.slice(0, 80), '...');
    await pool.query(sql);
  }
  console.log('Done. (Default checklist seed for demo-consultancy was applied separately — see Notion Config page for the seed list if you need to replicate it for a new tenant.)');
  await pool.end();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
