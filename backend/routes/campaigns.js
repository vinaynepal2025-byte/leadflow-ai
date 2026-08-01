const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// POST /campaigns  { name, message_template, source, stage }
// Targets are selected by filter (source/stage) at creation time — a
// snapshot, not a live query, so a campaign's target list doesn't shift
// under you after you've started sending.
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { name, message_template, source, stage } = req.body;
  if (!name || !message_template) {
    return res.status(400).json({ error: 'name and message_template are required' });
  }

  let query = 'SELECT id FROM leads WHERE tenant_id = ?';
  const params = [tid];
  if (source) {
    query += ' AND source = ?';
    params.push(source);
  }
  if (stage) {
    query += ' AND stage = ?';
    params.push(stage);
  }
  const targetLeads = await db.prepare(query).all(...params);

  const campaignId = randomUUID();
  await db.prepare('INSERT INTO campaigns (id, tenant_id, name, message_template) VALUES (?, ?, ?, ?)')
    .run(campaignId, tid, name, message_template);

  for (const lead of targetLeads) {
    await db.prepare('INSERT INTO campaign_targets (id, campaign_id, lead_id) VALUES (?, ?, ?)')
      .run(randomUUID(), campaignId, lead.id);
  }

  res.status(201).json({
    id: campaignId,
    name,
    message_template,
    status: 'draft',
    target_count: targetLeads.length,
  });
});

// GET /campaigns
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const campaigns = await db.prepare('SELECT * FROM campaigns WHERE tenant_id = ? ORDER BY created_at DESC').all(tid);
  const withCounts = await Promise.all(campaigns.map(async (c) => {
    const totalRow = await db.prepare('SELECT COUNT(*) AS c FROM campaign_targets WHERE campaign_id = ?').get(c.id);
    const sentRow = await db.prepare("SELECT COUNT(*) AS c FROM campaign_targets WHERE campaign_id = ? AND status = 'sent'").get(c.id);
    return { ...c, target_count: totalRow.c, sent_count: sentRow.c };
  }));
  res.json(withCounts);
});

// GET /campaigns/:id/links — generates a wa.me link per target lead,
// personalized from the message_template ({{name}} substitution).
// Free method (same as the single-lead wa.me feature) — no Meta API cost,
// counselor taps through the list and sends each one.
router.get('/:id/links', async (req, res) => {
  const tid = tenantId(req);
  const campaign = await db.prepare('SELECT * FROM campaigns WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!campaign) return res.status(404).json({ error: 'Campaign not found' });

  const targets = await db.prepare(`
    SELECT ct.id AS target_id, ct.status, l.id AS lead_id, l.full_name, l.phone
    FROM campaign_targets ct JOIN leads l ON l.id = ct.lead_id
    WHERE ct.campaign_id = ?
  `).all(req.params.id);

  const links = targets
    .filter((t) => t.phone)
    .map((t) => {
      const message = campaign.message_template.replace(/{{\s*name\s*}}/g, t.full_name);
      const cleanPhone = t.phone.replace(/[^0-9]/g, '');
      return {
        target_id: t.target_id,
        lead_id: t.lead_id,
        full_name: t.full_name,
        status: t.status,
        chat_link: `https://wa.me/${cleanPhone}?text=${encodeURIComponent(message)}`,
      };
    });

  res.json({ campaign_id: campaign.id, name: campaign.name, links });
});

// POST /campaigns/targets/:targetId/confirm-sent
router.post('/targets/:targetId/confirm-sent', async (req, res) => {
  await db.prepare("UPDATE campaign_targets SET status = 'sent' WHERE id = ?").run(req.params.targetId);
  res.json({ ok: true });
});

module.exports = router;
