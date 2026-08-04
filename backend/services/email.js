// Email Center — sends real email via Brevo's HTTP API (not raw SMTP).
// Render's free tier blocks all outbound SMTP ports (25, 465, 587) as of
// Sept 2025 -- confirmed via a live ENETUNREACH/timeout test, Aug 2026.
// Brevo's API rides over HTTPS (port 443), which is never blocked, so this
// works on Render's free tier with zero extra cost (300 emails/day free).
//
// Requires in .env:
//   BREVO_API_KEY      — from Brevo dashboard: Settings > SMTP & API > API Keys
//   BREVO_SENDER_EMAIL — a verified sender (Settings > Senders & IP > Senders)
//   BREVO_SENDER_NAME  — optional, defaults to "LeadFlow AI"

const BREVO_ENDPOINT = 'https://api.brevo.com/v3/smtp/email';

async function sendEmail(to, subject, text) {
  const { BREVO_API_KEY, BREVO_SENDER_EMAIL, BREVO_SENDER_NAME } = process.env;
  if (!BREVO_API_KEY || !BREVO_SENDER_EMAIL) {
    throw new Error('Email not configured yet. Set BREVO_API_KEY and BREVO_SENDER_EMAIL in .env.');
  }

  const res = await fetch(BREVO_ENDPOINT, {
    method: 'POST',
    headers: {
      'api-key': BREVO_API_KEY,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: JSON.stringify({
      sender: { email: BREVO_SENDER_EMAIL, name: BREVO_SENDER_NAME || 'LeadFlow AI' },
      to: [{ email: to }],
      subject,
      textContent: text,
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Brevo API error (${res.status}): ${body}`);
  }
  return res.json();
}

module.exports = { sendEmail };
