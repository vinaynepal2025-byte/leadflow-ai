require('dotenv').config();
const db = require('./db');
(async () => {
  await db.prepare("ALTER TABLE review_providers ADD COLUMN IF NOT EXISTS pricing_mode TEXT NOT NULL DEFAULT 'flat'").run();
  await db.prepare("ALTER TABLE review_providers ADD COLUMN IF NOT EXISTS rate_per_minute NUMERIC").run();
  await db.prepare("ALTER TABLE peer_review_bookings ADD COLUMN IF NOT EXISTS duration_minutes INTEGER").run();
  console.log('Migration applied successfully.');
  process.exit(0);
})().catch(e => { console.error('MIGRATION FAILED:', e.message); process.exit(1); });
