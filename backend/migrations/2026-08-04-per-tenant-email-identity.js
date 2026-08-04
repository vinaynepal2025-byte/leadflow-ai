require('dotenv').config();
const db = require('../db');
(async () => {
  await db.prepare("ALTER TABLE tenants ADD COLUMN IF NOT EXISTS email_reply_to TEXT").run();
  await db.prepare("ALTER TABLE tenants ADD COLUMN IF NOT EXISTS own_brevo_api_key_encrypted TEXT").run();
  await db.prepare("ALTER TABLE tenants ADD COLUMN IF NOT EXISTS own_brevo_sender_email TEXT").run();
  console.log('Migration applied.');
  process.exit(0);
})().catch(e => { console.error('MIGRATION FAILED:', e.message); process.exit(1); });
