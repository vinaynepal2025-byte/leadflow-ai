// Migration: 2026-08-13 — WhatsApp templates + scheduled messages + notes AI tagging (Phase 5)
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-13-whatsapp-notes-ai.js
//
// Note: schema + demo-consultancy default templates already applied
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
  `CREATE TABLE IF NOT EXISTS whatsapp_templates (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    name TEXT NOT NULL,
    body_text TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT now()
  )`,
  `CREATE TABLE IF NOT EXISTS scheduled_messages (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL REFERENCES tenants(id),
    lead_id TEXT NOT NULL REFERENCES leads(id),
    body_text TEXT NOT NULL,
    send_at TIMESTAMP NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_by TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    sent_at TIMESTAMP
  )`,
  `CREATE INDEX IF NOT EXISTS idx_scheduled_messages_due ON scheduled_messages(tenant_id, status, send_at)`,
  `ALTER TABLE lead_notes ADD COLUMN IF NOT EXISTS tags TEXT`,
  `ALTER TABLE lead_notes ADD COLUMN IF NOT EXISTS sentiment TEXT`,
];

(async () => {
  for (const sql of statements) {
    console.log('Running:', sql.slice(0, 80), '...');
    await pool.query(sql);
  }
  console.log('Done. (5 default WhatsApp templates for demo-consultancy were seeded separately — see Notion Config page to replicate for a new tenant.)');
  await pool.end();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
