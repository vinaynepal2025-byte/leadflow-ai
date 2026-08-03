// Email Center — sends real email via SMTP. Requires the consultancy's
// own email account credentials in .env:
//   SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM
// Works with Gmail (with an App Password), Outlook, or any SMTP provider —
// same honest pattern as WhatsApp/AI: real integration, needs your keys.

const nodemailer = require('nodemailer');

function getTransport() {
  const { SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS } = process.env;
  if (!SMTP_HOST || !SMTP_USER || !SMTP_PASS) {
    throw new Error('Email not configured yet. Set SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS in .env.');
  }
  return nodemailer.createTransport({
    host: SMTP_HOST,
    port: parseInt(SMTP_PORT || '587'),
    secure: SMTP_PORT === '465',
    auth: { user: SMTP_USER, pass: SMTP_PASS },
    // Render's outbound network can't route IPv6 -- Gmail (and some other
    // providers) resolve to an IPv6 address by default, causing a silent
    // ENETUNREACH. Forcing IPv4 here fixed it (confirmed live on Render,
    // Aug 2026 -- worked fine locally in Termux, which resolves differently,
    // so this class of bug only surfaces in production).
    family: 4,
  });
}

async function sendEmail(to, subject, text) {
  const transport = getTransport();
  const from = process.env.SMTP_FROM || process.env.SMTP_USER;
  return transport.sendMail({ from, to, subject, text });
}

module.exports = { sendEmail };
