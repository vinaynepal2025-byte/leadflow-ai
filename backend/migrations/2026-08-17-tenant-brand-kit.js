// Migration: 2026-08-17 — Brand Kit (Logo Studio Phase 9).
//
// BrandKitScreen already existed pre-session as a live, read-only
// overview (colours from AppearanceSettings, typography reference,
// a flat list of saved tenant_logos) -- a solid foundation, extended
// here rather than forked. What master spec §16 actually asks for and
// was missing: a way to designate WHICH saved logo plays which brand
// role (primary/secondary/monochrome/dark-background/light-background/
// icon mark) and a curated brand palette independent of the live app
// theme colours. One row per tenant in practice (the app upserts),
// though nothing at the DB level enforces that -- a future multi-brand
// tenant isn't blocked by this schema.
//
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-17-tenant-brand-kit.js

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
  `CREATE TABLE IF NOT EXISTS tenant_brand_kits (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    name TEXT NOT NULL DEFAULT 'Brand Kit',
    primary_logo_id UUID REFERENCES tenant_logos(id) ON DELETE SET NULL,
    secondary_logo_id UUID REFERENCES tenant_logos(id) ON DELETE SET NULL,
    mono_logo_id UUID REFERENCES tenant_logos(id) ON DELETE SET NULL,
    dark_bg_logo_id UUID REFERENCES tenant_logos(id) ON DELETE SET NULL,
    light_bg_logo_id UUID REFERENCES tenant_logos(id) ON DELETE SET NULL,
    icon_mark_logo_id UUID REFERENCES tenant_logos(id) ON DELETE SET NULL,
    palette JSONB NOT NULL DEFAULT '[]'::jsonb,
    font_primary TEXT,
    font_secondary TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now()
  )`,
  `CREATE INDEX IF NOT EXISTS idx_tenant_brand_kits_tenant ON tenant_brand_kits(tenant_id)`,
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
