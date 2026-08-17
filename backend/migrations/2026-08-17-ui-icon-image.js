// Migration: 2026-08-17 — Custom icon upload for Edit Mode tiles.
//
// Direct feedback: "icon upload ka bhi option do" -- so far icons on
// More Menu/Lead Detail/Share Target tiles were pick-one-from-a-fixed-
// Material-set only. icon_image_path stores an uploaded image's storage
// path (same Supabase Storage bucket as every other upload in this
// app); when set, LauncherTile renders it in place of the vector Icon.
// Null (the default) means "keep using icon_override/the built-in
// default", so no existing row changes behaviour until a tenant
// actually uploads something.
//
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-17-ui-icon-image.js

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
  `ALTER TABLE more_menu_items ADD COLUMN IF NOT EXISTS icon_image_path TEXT`,
  `ALTER TABLE lead_detail_sections ADD COLUMN IF NOT EXISTS icon_image_path TEXT`,
  `ALTER TABLE share_targets ADD COLUMN IF NOT EXISTS icon_image_path TEXT`,
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
