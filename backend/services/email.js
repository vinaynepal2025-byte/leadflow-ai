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
  });
}

async function sendEmail(to, subject, text) {
  const transport = getTransport();
  const from = process.env.SMTP_FROM || process.env.SMTP_USER;
  return transport.sendMail({ from, to, subject, text });
}

module.exports = { sendEmail };
