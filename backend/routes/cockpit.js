// backend/routes/cockpit.js
// Calling Cockpit — Phase 1
//
// Composes existing modules (leads, communications, calls, aiAnalysis,
// scoring) into one lead-focused workspace, plus 3 new pieces:
//   1. Next Best Action (reads full history, suggests what to do now)
//   2. Content Library + personalized Draft Engine (never a generic blast)
//   3. Send Queue (AI drafts everything, human taps "Send" — WhatsApp-safe)

const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { generateJson } = require('../services/aiProvider');
const { computeEngagementTrend } = require('../services/engagementTrend');
const { fireEvent } = require('../services/automationEngine');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// NOTE ON ROUTE ORDER (Express matches top-to-bottom): every literal path
// (e.g. /content, /offers) MUST be registered before the generic
// GET /:leadId catch-all below, or the catch-all will swallow it and try
// to look up a lead literally named "content". The generic GET /:leadId
// route is deliberately placed at the very END of this file — do not move
// it back up, and add any new literal single-segment GET route above it.

// ---------------------------------------------------------------------
// POST /cockpit/:leadId/next-best-action — AI reads everything and
// returns ONE recommended move (channel + reasoning), grounded in this
// specific lead's actual history, not a generic tip.
// ---------------------------------------------------------------------
router.post('/:leadId/next-best-action', async (req, res) => {
  const tid = tenantId(req);
  const { leadId } = req.params;

  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const communications = await db.prepare(
    'SELECT * FROM communications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at ASC'
  ).all(tid, leadId);

  const offers = await db.prepare(
    'SELECT * FROM offers WHERE tenant_id = ? AND lead_id = ? ORDER BY given_at DESC'
  ).all(tid, leadId);

  const historyText = communications
    .map((c) => `[${c.created_at}] ${c.direction} ${c.channel}: ${c.body || '(no text)'}`)
    .join('\n') || '(no interactions logged yet)';

  const offersText = offers
    .map((o) => `${o.offer_text} — ₹${o.amount || 'n/a'} (${o.status}, given ${o.given_at})`)
    .join('\n') || '(no offers made yet)';

  const trendResult = computeEngagementTrend(communications);
  await db.prepare('UPDATE leads SET engagement_trend = ? WHERE tenant_id = ? AND id = ?').run(trendResult.trend, tid, leadId);

  const daysSinceContact = lead.last_contacted_at
    ? Math.floor((Date.now() - new Date(lead.last_contacted_at).getTime()) / 86400000)
    : null;

  const prompt = `You are a senior admissions counselor's assistant. Read this lead's
full record and recommend exactly ONE next action — the single highest-leverage
move right now, not a generic checklist.

Lead: ${lead.full_name}, source: ${lead.source_category || lead.source || 'unknown'}, stage: ${lead.stage}
Days since last contact: ${daysSinceContact ?? 'never contacted'}
Computed engagement trend (rule-based, not a guess): ${trendResult.trend} — ${trendResult.reasoning}
Notes on file: ${lead.notes || 'none'}

Interaction history (chronological):
${historyText}

Offers made so far:
${offersText}

Respond ONLY with valid JSON, no other text, in exactly this shape:
{
  "recommended_channel": "whatsapp | call | email",
  "urgency": "today | this_week | low",
  "reasoning": "1-2 sentences on WHY this is the right move, referencing something specific from their history",
  "talking_points": ["3 short, specific bullet points for this exact lead"],
  "engagement_read": "rising | steady | cooling | cold",
  "risk_flag": "short phrase if there's a concern (e.g. 'mentioned a competing consultancy'), or null"
}`;

  try {
    const result = await generateJson(prompt, { maxTokens: 2000 });
    res.json(result);
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// ---------------------------------------------------------------------
// Offers — track what was promised, how much, when
// ---------------------------------------------------------------------
router.get('/offers/:leadId', async (req, res) => {
  const tid = tenantId(req);
  const rows = await db.prepare(
    'SELECT * FROM offers WHERE tenant_id = ? AND lead_id = ? ORDER BY given_at DESC'
  ).all(tid, req.params.leadId);
  res.json(rows);
});

router.post('/offers', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, offer_text, amount, currency, given_by, valid_until, notes } = req.body;
  if (!lead_id || !offer_text) return res.status(400).json({ error: 'lead_id and offer_text are required' });

  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO offers (id, tenant_id, lead_id, offer_text, amount, currency, given_by, valid_until, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, offer_text, amount || null, currency || 'INR', given_by || null, valid_until || null, notes || null);

  // Mirror into Communication Hub so the unified timeline picks it up.
  await db.prepare(`
    INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
    VALUES (?, ?, ?, 'note', 'outbound', ?, ?)
  `).run(randomUUID(), tid, lead_id, `Offer given: ${offer_text}${amount ? ` (₹${amount})` : ''}`, given_by || null);

  fireEvent('offer.given', { tenant_id: tid, lead_id, offer_text, amount }).catch((err) =>
    console.error('offer.given automation failed (offer itself was still saved):', err.message)
  );

  res.status(201).json(await db.prepare('SELECT * FROM offers WHERE id = ?').get(id));
});

router.patch('/offers/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT * FROM offers WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Offer not found' });

  const { status } = req.body;
  if (status) {
    await db.prepare('UPDATE offers SET status = ? WHERE tenant_id = ? AND id = ?').run(status, tid, req.params.id);
  }
  res.json(await db.prepare('SELECT * FROM offers WHERE id = ?').get(req.params.id));
});

// ---------------------------------------------------------------------
// Content Library — reusable flyers/links/PDFs, tagged for the draft
// engine to select from per-lead (never a blind blast template)
// ---------------------------------------------------------------------
router.get('/content', async (req, res) => {
  const tid = tenantId(req);
  const rows = await db.prepare(
    'SELECT * FROM content_library WHERE tenant_id = ? AND active = true ORDER BY created_at DESC'
  ).all(tid);
  res.json(rows);
});

router.post('/content', async (req, res) => {
  const tid = tenantId(req);
  const { title, content_type, file_url, link_url, body_text, tags, language } = req.body;
  if (!title || !content_type) return res.status(400).json({ error: 'title and content_type are required' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO content_library (id, tenant_id, title, content_type, file_url, link_url, body_text, tags, language)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, title, content_type, file_url || null, link_url || null, body_text || null, JSON.stringify(tags || []), language || 'en');

  res.status(201).json(await db.prepare('SELECT * FROM content_library WHERE id = ?').get(id));
});

// ---------------------------------------------------------------------
// POST /cockpit/:leadId/draft — the personalization core. AI picks the
// right content (or none) from the library and writes a one-off message
// for THIS lead — never the same draft twice for two different leads.
// ---------------------------------------------------------------------
router.post('/:leadId/draft', async (req, res) => {
  const tid = tenantId(req);
  const { leadId } = req.params;
  const { channel } = req.body; // whatsapp | email

  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const communications = await db.prepare(
    'SELECT * FROM communications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at ASC'
  ).all(tid, leadId);

  const library = await db.prepare(
    'SELECT * FROM content_library WHERE tenant_id = ? AND active = true'
  ).all(tid);

  const alreadySent = await db.prepare(
    'SELECT content_id FROM content_sends WHERE tenant_id = ? AND lead_id = ?'
  ).all(tid, leadId);
  const alreadySentIds = new Set(alreadySent.map((r) => r.content_id));

  const availableContent = library.filter((c) => !alreadySentIds.has(c.id));

  const historyText = communications
    .map((c) => `[${c.created_at}] ${c.direction} ${c.channel}: ${c.body || '(no text)'}`)
    .join('\n') || '(no interactions logged yet)';

  const libraryText = availableContent
    .map((c) => `id=${c.id} | type=${c.content_type} | title="${c.title}" | tags=${c.tags}`)
    .join('\n') || '(no unsent content available — text-only reply)';

  const prompt = `You are drafting a personalized ${channel || 'whatsapp'} message for ONE specific
admissions lead. This must NOT read like a template — write it as if you know this
exact person's situation from their history below.

Lead: ${lead.full_name}, stage: ${lead.stage}, notes: ${lead.notes || 'none'}

Interaction history:
${historyText}

Available content library (pick 0 or 1 item ONLY if it genuinely fits what this
lead needs right now — do not force an attachment they haven't asked for or need):
${libraryText}

Respond ONLY with valid JSON, no other text, in exactly this shape:
{
  "message_text": "the actual message, warm and professional, personalized to this lead",
  "attach_content_id": "id from the library above, or null if text-only is right",
  "reasoning": "1 sentence on why this content choice (or no attachment)"
}`;

  try {
    const draft = await generateJson(prompt, { maxTokens: 2000 });
    res.json(draft);
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// ---------------------------------------------------------------------
// POST /cockpit/:leadId/confirm-send — call this AFTER the counselor
// taps "Send" in WhatsApp/email themselves (this endpoint logs it, it
// does NOT send anything itself — see README note on WhatsApp safety).
// ---------------------------------------------------------------------
router.post('/:leadId/confirm-send', async (req, res) => {
  const tid = tenantId(req);
  const { leadId } = req.params;
  const { channel, draft_text, content_id, sent_by } = req.body;
  if (!channel || !draft_text) return res.status(400).json({ error: 'channel and draft_text are required' });

  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  await db.prepare(`
    INSERT INTO content_sends (id, tenant_id, lead_id, content_id, channel, draft_text, sent_by)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(randomUUID(), tid, leadId, content_id || null, channel, draft_text, sent_by || null);

  await db.prepare(`
    INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
    VALUES (?, ?, ?, ?, 'outbound', ?, ?)
  `).run(randomUUID(), tid, leadId, channel, draft_text, sent_by || null);

  await db.prepare('UPDATE leads SET last_contacted_at = now() WHERE tenant_id = ? AND id = ?').run(tid, leadId);

  res.status(201).json({ logged: true });
});

// ---------------------------------------------------------------------
// GET /cockpit/send-queue — today's pending drafts across ALL leads that
// need a follow-up (reminder due, or cooling-engagement flag) — the
// swipe-and-tap workflow. Each item still needs POST /draft to generate
// text (kept separate so drafts stay fresh/on-demand, not stale/cached).
// ---------------------------------------------------------------------
router.get('/send-queue/today', async (req, res) => {
  const tid = tenantId(req);
  const rows = await db.prepare(`
    SELECT l.id, l.full_name, l.stage, l.source_category, l.last_contacted_at, l.engagement_trend
    FROM leads l
    WHERE l.tenant_id = ?
      AND l.stage NOT IN ('Closed', 'Lost')
      AND (
        l.last_contacted_at IS NULL
        OR l.last_contacted_at < now() - INTERVAL '3 days'
      )
    ORDER BY l.last_contacted_at ASC NULLS FIRST
    LIMIT 50
  `).all(tid);
  res.json(rows);
});

// ---------------------------------------------------------------------
// GET /cockpit/:leadId/engagement-trend — rule-based (not AI), silent-churn
// detector. Updates leads.engagement_trend so it's visible elsewhere
// (e.g. send-queue) without recomputing every time.
// ---------------------------------------------------------------------
router.get('/:leadId/engagement-trend', async (req, res) => {
  const tid = tenantId(req);
  const { leadId } = req.params;

  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const communications = await db.prepare(
    'SELECT * FROM communications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at ASC'
  ).all(tid, leadId);

  const result = computeEngagementTrend(communications);
  await db.prepare('UPDATE leads SET engagement_trend = ? WHERE tenant_id = ? AND id = ?').run(result.trend, tid, leadId);

  res.json(result);
});

// ---------------------------------------------------------------------
// GET /cockpit/:leadId — full cockpit view for one lead: profile, history,
// offers, and AI Next Best Action in a single call (mobile-screen friendly —
// one request, not five).
// MUST stay last — see route-order note near the top of this file.
// ---------------------------------------------------------------------
router.get('/:leadId', async (req, res) => {
  const tid = tenantId(req);
  const { leadId } = req.params;

  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const communications = await db.prepare(
    'SELECT * FROM communications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at ASC'
  ).all(tid, leadId);

  const offers = await db.prepare(
    'SELECT * FROM offers WHERE tenant_id = ? AND lead_id = ? ORDER BY given_at DESC'
  ).all(tid, leadId);

  const sentContent = await db.prepare(
    'SELECT content_id FROM content_sends WHERE tenant_id = ? AND lead_id = ?'
  ).all(tid, leadId);

  res.json({
    lead,
    communications,
    offers,
    already_sent_content_ids: sentContent.map((r) => r.content_id),
  });
});

module.exports = router;
