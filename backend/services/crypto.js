// Encrypt/decrypt helpers for storing per-tenant secrets (e.g. their own
// Brevo API key) at rest in Postgres. AES-256-GCM: authenticated encryption,
// so tampering with stored ciphertext is detected, not just hidden.
//
// Requires MASTER_KEY in .env — a 64-character hex string (32 bytes).
// Generate one with: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
// This key must NEVER be committed to git, and losing it means every
// encrypted value stored using it becomes permanently unrecoverable.

const crypto = require('crypto');

function getKey() {
  const key = process.env.MASTER_KEY;
  if (!key) throw new Error('MASTER_KEY not set in .env');
  const buf = Buffer.from(key, 'hex');
  if (buf.length !== 32) throw new Error('MASTER_KEY must be a 64-character hex string (32 bytes)');
  return buf;
}

function encrypt(plaintext) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', getKey(), iv);
  const encrypted = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();
  // Store iv + authTag + ciphertext together, base64-encoded, as one string.
  return Buffer.concat([iv, authTag, encrypted]).toString('base64');
}

function decrypt(payload) {
  const data = Buffer.from(payload, 'base64');
  const iv = data.subarray(0, 12);
  const authTag = data.subarray(12, 28);
  const encrypted = data.subarray(28);
  const decipher = crypto.createDecipheriv('aes-256-gcm', getKey(), iv);
  decipher.setAuthTag(authTag);
  return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString('utf8');
}

module.exports = { encrypt, decrypt };
