// Migration: 2026-08-17 — Rich Edit Mode styling (style_json).
//
// The existing per-item customization (color_override, gradient_override,
// style_variant -- one of 4 fixed preset looks: flat/gradient_badge/glow/
// glass) was reported as too limited: "resize, color, gradient, texture,
// style, sharpness, edge control, glow, blur ... customizable studio
// jaisa". Rather than adding a new column per new knob across three
// tables (a schema explosion), this adds one extensible JSONB column --
// same reasoning as flyer_projects.canvas_json -- holding whichever of
// {cornerRadius, borderColor, borderWidth, glowColor, glowIntensity,
// blurAmount, contentScale, textureId} the user has actually set. Empty
// object means "use the style_variant preset's defaults, no fine-tuning
// applied yet" -- fully backward compatible, no existing row changes
// behaviour until edited.
//
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-08-17-ui-style-json.js

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
  `ALTER TABLE more_menu_items ADD COLUMN IF NOT EXISTS style_json JSONB NOT NULL DEFAULT '{}'::jsonb`,
  `ALTER TABLE lead_detail_sections ADD COLUMN IF NOT EXISTS style_json JSONB NOT NULL DEFAULT '{}'::jsonb`,
  `ALTER TABLE share_targets ADD COLUMN IF NOT EXISTS style_json JSONB NOT NULL DEFAULT '{}'::jsonb`,
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
