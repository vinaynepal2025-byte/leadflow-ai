// Migration: 2026-09-03 — lead_notes AI-remarks columns + leads alternate contact
// Idempotent, matches the established migration pattern.
// Run with: node migrations/2026-09-03-lead-remarks-and-alternate-contact.js
//
// NOT YET APPLIED. Draft only — schema confirmed live via supabase-primary
// before writing this file (see below), nothing assumed.

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

// --- lead_notes: remarks_raw / remarks_final -------------------------------
//
// Confirmed live schema before adding these (9 existing columns, no
// conflicts): id (uuid PK), tenant_id, lead_id (both text, NOT NULL, no FK
// constraint currently enforced on either — a pre-existing gap, unrelated
// to this migration), note_text (text, NOT NULL), author_name, pinned,
// created_at, tags, sentiment. Only constraint on the table is the id
// primary key.
//
// remarks_raw / remarks_final are added here as plain nullable TEXT columns
// -- regular notes (created via the existing POST /lead-notes flow) will
// simply leave both NULL, exactly like tags/sentiment already do for any
// note the AI classifier couldn't confidently tag.
//
// NOTE FOR THE FUTURE REMARKS-INSERT ROUTE (not built in this migration):
// note_text is NOT NULL, so whatever route creates an AI-rewritten remark
// entry must still populate note_text (expected: note_text = remarks_final)
// so it displays correctly in the existing lead notes list UI without any
// changes there.
//
// No new type/source column was added to distinguish an AI-rewritten
// remark from a regular typed note. Reasoning: `remarks_raw IS NOT NULL` is
// already a complete, reliable signal on its own -- a regular note will
// never populate it, an AI-rewritten remark always will. A separate
// `source`/`type` enum would duplicate information already inferable from
// column nullability (the same pattern this table already uses for
// tags/sentiment -- there's no separate "was this note AI-classified?"
// flag either, NULL already means "no"), and would be one more field every
// future query has to keep in sync for no added guarantee. Revisit only if
// a real need for filtering/reporting specifically on remark-vs-note
// volume shows up later.
const leadNotesRemarks = [
  `ALTER TABLE lead_notes ADD COLUMN IF NOT EXISTS remarks_raw TEXT`,
  `ALTER TABLE lead_notes ADD COLUMN IF NOT EXISTS remarks_final TEXT`,
];

// --- leads: alternate_phone / alternate_phone_country_code -----------------
//
// Unrelated to the remarks change above -- this is for the Alternate
// contact's WhatsApp/dialer icons. Mirrors the existing phone /
// phone_country_code pair exactly (confirmed live: leads.phone and
// leads.phone_country_code are both nullable text columns already), so
// backend/services/phone.js's buildWhatsAppLink()/toE164() can be called
// against the alternate pair with zero changes to that function itself --
// only the call site needs to pass alternate_phone /
// alternate_phone_country_code instead of phone / phone_country_code when
// building the Alternate contact's link.
const leadsAlternateContact = [
  `ALTER TABLE leads ADD COLUMN IF NOT EXISTS alternate_phone TEXT`,
  `ALTER TABLE leads ADD COLUMN IF NOT EXISTS alternate_phone_country_code TEXT`,
];

const statements = [...leadNotesRemarks, ...leadsAlternateContact];

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
