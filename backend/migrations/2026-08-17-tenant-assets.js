// Migration: 2026-08-17 — Tenant Asset Library (Logo Studio Phase 5).
//
// Phase 1 audit: "No generic 'asset library' concept exists -- no shared
// media/asset table, no reusable-across-projects image gallery."
// tenant_assets is that missing piece: one place to save an icon/image/
// logo/export from any Flyer/Logo Studio project and reuse it in another,
// instead of every project re-uploading or re-picking the same graphic.
//
// An asset is either a stored file (storage_path, via Supabase Storage --
// images, logos, exports) or raw vector markup (svg_data, for SVG assets
// saved straight from the canvas) -- never both, so kind alone tells a
// client which field to read.
//
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-17-tenant-assets.js

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
  `CREATE TABLE IF NOT EXISTS tenant_assets (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    kind TEXT NOT NULL,
    label TEXT,
    category TEXT,
    storage_path TEXT,
    svg_data TEXT,
    is_favorite BOOLEAN NOT NULL DEFAULT false,
    created_by TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    updated_at TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT tenant_assets_kind_check CHECK (kind IN ('icon', 'image', 'logo', 'export', 'svg')),
    CONSTRAINT tenant_assets_has_content CHECK (storage_path IS NOT NULL OR svg_data IS NOT NULL)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_tenant_assets_tenant ON tenant_assets(tenant_id, kind, created_at DESC)`,
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
