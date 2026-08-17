// Migration: 2026-08-17 — Rich styling for the Leads List's Stage chip
// (Logo Studio session's Edit Mode styling extended to the Leads screen).
//
// lead_list_fields had no visual styling at all before this -- its
// 7 rows are pure show/hide/reorder toggles for plain-text subtitle
// fields and two badges. Of those two, only the Stage chip (StageChip
// widget) is a real "boxed" element with a shape worth styling; the
// Score badge is inline icon+text with no container. This column
// mirrors the style_json added to more_menu_items/lead_detail_sections/
// share_targets in the same pass, but deliberately does NOT add a
// colour override here -- StageChip's colour is meaningful information
// (stage-coded), and overriding it with one flat colour would destroy
// that at-a-glance signal. style_json's structural properties (corner
// radius/border/glow/blur) layer on top of the existing per-stage
// colour instead of replacing it.
//
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-17-lead-list-fields-style-json.js

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
  `ALTER TABLE lead_list_fields ADD COLUMN IF NOT EXISTS style_json JSONB NOT NULL DEFAULT '{}'::jsonb`,
];

(async () => {
  for (const sql of statements) {
    console.log('Running:', sql.slice(0, 90), '...');
    await pool.query(sql);
  }
  console.log('Done.');
  await pool.end();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
