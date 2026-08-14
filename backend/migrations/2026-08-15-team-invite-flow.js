// Migration: 2026-08-15 — Team member email-invite flow
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-15-team-invite-flow.js
//
// Note: schema already applied directly to the live Supabase DB via MCP
// during this session -- this file is the committed record.

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
  `ALTER TABLE users ADD COLUMN IF NOT EXISTS invite_token TEXT`,
  `ALTER TABLE users ADD COLUMN IF NOT EXISTS invite_token_expires_at TIMESTAMP`,
  `CREATE INDEX IF NOT EXISTS idx_users_invite_token ON users(invite_token)`,
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
