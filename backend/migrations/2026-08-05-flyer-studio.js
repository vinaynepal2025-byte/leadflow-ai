// Migration: 2026-08-05 — Flyer Studio (Phase 5)
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-05-flyer-studio.js

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
  `CREATE TABLE IF NOT EXISTS flyers (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT REFERENCES leads(id),
    template_id TEXT NOT NULL,
    fields TEXT NOT NULL,
    -- JSON of the text fields used to generate this flyer, so it can be
    -- regenerated/edited later without losing the original inputs
    png_base64 TEXT NOT NULL,
    ai_generated BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP NOT NULL DEFAULT now()
  )`,
  `CREATE INDEX IF NOT EXISTS idx_flyers_tenant ON flyers(tenant_id, created_at DESC)`,
];

(async () => {
  const client = await pool.connect();
  try {
    for (const sql of statements) {
      await client.query(sql);
      console.log('OK:', sql.split('\n')[0].slice(0, 70));
    }
    console.log('\n✅ Flyer Studio migration complete.');
  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
})();
