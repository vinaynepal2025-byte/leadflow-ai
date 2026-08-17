// Migration: 2026-08-17 — Dashboard customization (per-screen customize,
// same pattern as lead_detail_sections)
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-17-dashboard-sections.js

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
  `CREATE TABLE IF NOT EXISTS dashboard_sections (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    section_key TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT true,
    sort_order INTEGER NOT NULL DEFAULT 0,
    color_override TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, section_key)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_dashboard_sections_tenant ON dashboard_sections(tenant_id, sort_order)`,
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
