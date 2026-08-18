// Migration: 2026-08-17 — Flyer/Logo Studio schema baseline.
//
// flyer_projects and tenant_logos have been live in production since
// before this migrations directory's coverage started (per
// ARCHITECTURE_MAP.md: "most tables created inline... no single
// authoritative schema file") -- LOGO_STUDIO_ARCHITECTURE.md's Phase 1
// audit flagged this as a real gap: neither table had a migration file
// to bootstrap a fresh dev/staging environment from.
//
// This file is NOT meant to change production (both tables already
// exist there with exactly this shape, verified via a live schema
// query) -- CREATE TABLE IF NOT EXISTS makes it a safe no-op if run
// against the existing database, and its real purpose is making a
// fresh environment reproducible from migrations alone.
//
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-17-flyer-logo-schema-baseline.js

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
  `CREATE TABLE IF NOT EXISTS flyer_projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id TEXT NOT NULL,
    lead_id TEXT,
    title TEXT DEFAULT 'Untitled Flyer',
    canvas_width INTEGER DEFAULT 1080,
    canvas_height INTEGER DEFAULT 1350,
    canvas_json JSONB NOT NULL DEFAULT '[]'::jsonb,
    background_color TEXT DEFAULT '#FFFFFF',
    background_image_path TEXT,
    rendered_image_path TEXT,
    ai_generated BOOLEAN DEFAULT false,
    created_by TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
  )`,
  `CREATE INDEX IF NOT EXISTS idx_flyer_projects_tenant ON flyer_projects(tenant_id, updated_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_flyer_projects_lead ON flyer_projects(tenant_id, lead_id)`,
  `CREATE TABLE IF NOT EXISTS tenant_logos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id TEXT NOT NULL,
    label TEXT,
    storage_path TEXT NOT NULL,
    is_default BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
  )`,
  `CREATE INDEX IF NOT EXISTS idx_tenant_logos_tenant ON tenant_logos(tenant_id)`,
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
