// Email Center — sends real email via Brevo's HTTP API (not raw SMTP).
// Render's free tier blocks all outbound SMTP ports (25, 465, 587) as of
// Sept 2025 -- confirmed via a live ENETUNREACH/timeout test, Aug 2026.
// Brevo's API rides over HTTPS (port 443), which is never blocked, so this
// works on Render's free tier with zero extra cost (300 emails/day free).
//
// Requires in .env (platform default, used when a tenant hasn't set up
// their own email identity):
//   BREVO_API_KEY      — from Brevo dashboard: Settings > SMTP & API > API Keys
//   BREVO_SENDER_EMAIL — a verified sender (Settings > Senders & IP > Senders)
//   BREVO_SENDER_NAME  — optional, defaults to "LeadFlow AI"
//
// Per-tenant email identity (optional, two tiers):
//   Tier 1 (zero setup): pass the tenant row and it'll use tenant.name as
//     the display name and tenant.email_reply_to (if set) as Reply-To --
//     still sends through the platform's Brevo account.
//   Tier 2 (advanced, opt-in): if the tenant has their own encrypted Brevo
//     API key + sender email (own_brevo_api_key_encrypted /
//     own_brevo_sender_email, set via PATCH /settings/email-provider),
//     the email is sent through THEIR OWN Brevo account instead --
//     fully white-label sender address, not just a display name.

const { decrypt } = require('./crypto');

const BREVO_ENDPOINT = 'https://api.brevo.com/v3/smtp/email';

async function sendEmail(to, subject, text, tenant) {
  let apiKey = process.env.BREVO_API_KEY;
  let senderEmail = process.env.BREVO_SENDER_EMAIL;
  const senderName = tenant?.name || process.env.BREVO_SENDER_NAME || 'LeadFlow AI';

  if (tenant?.own_brevo_api_key_encrypted && tenant?.own_brevo_sender_email) {
    // Tier 2: this tenant brought their own Brevo account -- use it instead
    // of the platform's, so the email is fully theirs (sender address too,
    // not just a display name).
    apiKey = decrypt(tenant.own_brevo_api_key_encrypted);
    senderEmail = tenant.own_brevo_sender_email;
  }

  if (!apiKey || !senderEmail) {
    throw new Error('Email not configured yet. Set BREVO_API_KEY and BREVO_SENDER_EMAIL in .env.');
  }

  const body = {
    sender: { email: senderEmail, name: senderName },
    to: [{ email: to }],
    subject,
    textContent: text,
  };
  if (tenant?.email_reply_to) {
    body.replyTo = { email: tenant.email_reply_to };
  }

  const res = await fetch(BREVO_ENDPOINT, {
    method: 'POST',
    headers: {
      'api-key': apiKey,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errBody = await res.text();
    throw new Error(`Brevo API error (${res.status}): ${errBody}`);
  }
  return res.json();
}

module.exports = { sendEmail };
