// backend/routes/leadAdsWebhook.js
// Facebook/Instagram Lead Ads — Phase 6, Chunk 4.
//
// Same verification-handshake + webhook pattern as whatsappWebhook.js.
// Same honest multi-tenant simplification that file already has: which
// tenant owns which Facebook Page isn't resolved here yet (would need a
// page_id -> tenant_id mapping, a Module-5-style multi-tenant concern) —
// simplified to the demo tenant for now, same as whatsappWebhook.js.

const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { fetchLeadDetails } = require('../services/facebookLeadAds');
const { createNotification } = require('./notifications');
const { fireEvent } = require('../services/automationEngine');
const { verifyMetaSignature } = require('../services/webhookSecurity');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || req.query.tenant_id || 'demo-consultancy';
}

// GET /lead-ads/webhook — Meta's one-time verification handshake
router.get('/webhook', (req, res) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];
  const expectedToken = process.env.LEAD_ADS_VERIFY_TOKEN;

  if (mode === 'subscribe' && token === expectedToken) {
    return res.status(200).send(challenge);
  }
  return res.sendStatus(403);
});

// POST /lead-ads/webhook — fired by Meta whenever someone submits a lead form
router.post('/webhook', async (req, res) => {
  if (!verifyMetaSignature(req, { secretEnvVar: 'LEAD_ADS_APP_SECRET', webhookName: 'Lead Ads' })) {
    return res.sendStatus(401);
  }

  res.sendStatus(200); // ack immediately — Meta retries on a slow/failed response

  try {
    const entry = req.body.entry?.[0];
    const changes = entry?.changes || [];

    for (const change of changes) {
      if (change.field !== 'leadgen') continue;
      const leadgenId = change.value?.leadgen_id;
      if (!leadgenId) continue;

      const fields = await fetchLeadDetails(leadgenId);
      const tid = tenantId(req);

      const fullName = fields.full_name || fields['full name'] || 'Facebook Lead';
      const phone = fields.phone_number || fields.phone || null;
      const email = fields.email || null;

      const id = randomUUID();
      await db.prepare(`
        INSERT INTO leads (id, tenant_id, full_name, phone, email, source, source_category, stage, notes, lifecycle_status)
        VALUES (?, ?, ?, ?, ?, 'Facebook/Instagram Lead Ad', 'lead_ads', 'New', ?, 'NEW')
      `).run(id, tid, fullName, phone, email, JSON.stringify(fields));

      await createNotification(tid, {
        title: 'New lead from Facebook/Instagram Ad',
        body: fullName,
        linkType: 'lead',
        linkId: id,
      });

      fireEvent('lead.created', { tenant_id: tid, lead_id: id }).catch((err) =>
        console.error('lead.created automation failed (lead itself was still saved):', err.message)
      );

      console.log(`New Lead Ads lead created: ${fullName} (leadgen_id ${leadgenId})`);
    }
  } catch (err) {
    console.error('Lead Ads webhook processing error:', err.message);
  }
});

// GET /lead-ads/status — same fail-closed pattern as /whatsapp/status
router.get('/status', (req, res) => {
  const configured = Boolean(process.env.FACEBOOK_PAGE_ACCESS_TOKEN && process.env.LEAD_ADS_VERIFY_TOKEN);
  res.json({ configured });
});

module.exports = router;
