// Meta signs every inbound webhook POST body with the receiving app's App
// Secret and sends the result as `X-Hub-Signature-256: sha256=<hex hmac>`.
// Verifying it is the only way to know a request genuinely came from Meta
// and not a forged POST to a guessable public URL -- see
// LEADS_AUTOMATION_AUDIT.md section 6, which found both whatsappWebhook.js
// and leadAdsWebhook.js only checked the one-time GET verify-token and
// never validated a single POST.
//
// Same honest "not configured" house style as whatsapp.js/payments.js:
// if the secret isn't set yet, we don't silently pretend the endpoint is
// secure -- we log it loudly on every request and let the request
// through unsigned, so a deploy that hasn't added the secret to Render
// yet doesn't suddenly start rejecting real Meta traffic. Once the
// secret is set, verification is strict: a missing or wrong signature is
// rejected with 401.

const crypto = require('crypto');

function verifyMetaSignature(req, { secretEnvVar, webhookName }) {
  const secret = process.env[secretEnvVar] || process.env.META_APP_SECRET;
  if (!secret) {
    console.warn(
      `[webhookSecurity] ${secretEnvVar} (or META_APP_SECRET) is not set -- ` +
      `the ${webhookName} webhook's signature is NOT being verified. Any ` +
      `request to this URL is currently trusted as if it came from Meta. ` +
      `Set META_APP_SECRET (Meta App Dashboard > Settings > Basic > App ` +
      `Secret) in the backend environment to close this gap.`
    );
    return true; // fail-open until configured -- see file header
  }

  const signatureHeader = req.get('x-hub-signature-256');
  if (!signatureHeader || !req.rawBody) {
    console.error(`[webhookSecurity] Rejected ${webhookName} webhook POST: missing signature header or raw body.`);
    return false;
  }

  const expected = `sha256=${crypto.createHmac('sha256', secret).update(req.rawBody).digest('hex')}`;
  const a = Buffer.from(signatureHeader);
  const b = Buffer.from(expected);
  const valid = a.length === b.length && crypto.timingSafeEqual(a, b);
  if (!valid) {
    console.error(`[webhookSecurity] Rejected ${webhookName} webhook POST: signature mismatch.`);
  }
  return valid;
}

module.exports = { verifyMetaSignature };
