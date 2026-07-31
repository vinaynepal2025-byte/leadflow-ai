const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { createNotification } = require('./notifications');
const { handleInboundForTriage } = require('../services/smartTriage');

const router = express.Router();

// Meta requires a webhook that:
// 1. Responds to a GET verification handshake once, when you register the URL
//    in Meta App Dashboard > WhatsApp > Configuration > Webhook.
// 2. Receives POST events for every inbound message after that.
//
// This webhook needs a real public HTTPS URL to register with Meta — it
// can't be verified from localhost. Once this backend is deployed
// (Module 5, deployment step), the URL will be e.g.
// https://your-domain.com/whatsapp/webhook — set WEBHOOK_VERIFY_TOKEN in
// .env to any secret string of your choice; Meta echoes it back on setup.

// GET /whatsapp/webhook — Meta's one-time verification handshake
router.get('/webhook', (req, res) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];

  const expectedToken = process.env.WEBHOOK_VERIFY_TOKEN;

  if (mode === 'subscribe' && token === expectedToken) {
    return res.status(200).send(challenge);
  }
  return res.sendStatus(403);
});

// POST /whatsapp/webhook — inbound message events from Meta
router.post('/webhook', (req, res) => {
  // Always acknowledge immediately — Meta retries if it doesn't get a fast 200.
  res.sendStatus(200);

  try {
    const entry = req.body.entry?.[0];
    const change = entry?.changes?.[0];
    const value = change?.value;
    const messages = value?.messages;
    if (!messages || messages.length === 0) return; // status update, not a message

    for (const msg of messages) {
      const fromPhone = msg.from; // sender's phone, digits only, with country code
      const text = msg.text?.body || `[${msg.type} message]`;

      // Match this inbound message to an existing lead by phone number.
      // Multi-tenant note: in production, which tenant owns which WhatsApp
      // number is looked up here too (one WABA phone number per tenant) —
      // simplified to the demo tenant until Module 5 (multi-tenant routing).
      const lead = db.prepare(
        "SELECT * FROM leads WHERE phone LIKE '%' || ? OR phone = ?"
      ).get(fromPhone.slice(-10), fromPhone);

      if (lead) {
        const id = randomUUID();
        db.prepare(`
          INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
          VALUES (?, ?, ?, 'whatsapp', 'inbound', ?, 'system-webhook')
        `).run(id, lead.tenant_id, lead.id, text);
        createNotification(lead.tenant_id, {
          title: `New WhatsApp reply from ${lead.full_name}`,
          body: text,
          linkType: 'lead',
          linkId: lead.id,
        });
        console.log(`Logged inbound WhatsApp from ${lead.full_name}: ${text}`);

        // Smart Triage: off by default (a consultancy should opt in
        // deliberately, since it means the app may speak to a lead
        // without a human reading first). Enable via .env.
        if (process.env.AUTO_TRIAGE_ENABLED === 'true') {
          handleInboundForTriage(lead.tenant_id, lead, text).catch((err) =>
            console.error('Smart triage failed (message already logged, no data lost):', err.message));
        }
      } else {
        console.log(`Inbound WhatsApp from unknown number ${fromPhone}: ${text} (no matching lead)`);
      }
    }
  } catch (err) {
    console.error('Webhook processing error:', err.message);
  }
});

module.exports = router;
