// backend/routes/flyers.js
// Flyer Studio — Phase 5
//
// SVG templates (flyerTemplates.js, zero native deps) rendered to PNG via
// `sharp` (industry-standard, prebuilt binaries — see session notes on
// why this was chosen over Canva Enterprise's Autofill API, which costs
// $15k-50k+/year and is wildly disproportionate for a solo consultancy).
//
// Flow:
//   1. Manual: counselor fills fields directly -> POST /generate
//   2. AI-assisted: Gemini writes the copy from real lead/offer context
//      (same grounding pattern as cockpit.js's draft engine) -> POST /quick-generate
//   3. POST /save persists the PNG (base64 in Postgres — no paid storage
//      needed at this volume) and returns a real, shareable image URL
//   4. That URL can be opened in a browser, downloaded, and manually
//      uploaded to Canva for further polish — no Canva API needed for
//      this "raw work then polish" workflow the free tier doesn't block.

const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { listTemplates, renderTemplate } = require('../services/flyerTemplates');
const { generateJson } = require('../services/aiProvider');

const router = express.Router();

// sharp is loaded LAZILY (not at module load time) — deliberate safety
// choice: if sharp fails to load on some platform/environment, the rest
// of the backend (leads, cockpit, everything else) keeps running. Only
// the flyer-image routes fail, with a clear error, instead of taking
// down the whole server.
let sharpModule = null;
let sharpLoadError = null;
function getSharp() {
  if (sharpModule) return sharpModule;
  if (sharpLoadError) throw sharpLoadError;
  try {
    sharpModule = require('sharp');
    return sharpModule;
  } catch (err) {
    sharpLoadError = err;
    throw err;
  }
}

function tenantId(req) {
  return req.header('x-tenant-id') || req.query.tenant_id || 'demo-consultancy';
}

// GET /flyers/templates
router.get('/templates', (req, res) => {
  res.json(listTemplates());
});

// POST /flyers/generate  { template_id, fields }
// Renders immediately, returns a base64 PNG data URI for instant preview
// — NOT saved yet, so the counselor can iterate freely before committing.
router.post('/generate', async (req, res) => {
  const { template_id, fields } = req.body;
  if (!template_id || !fields) return res.status(400).json({ error: 'template_id and fields are required' });

  try {
    const svg = renderTemplate(template_id, fields);
    const png = await getSharp()(Buffer.from(svg)).png().toBuffer();
    res.json({ image_data_uri: `data:image/png;base64,${png.toString('base64')}`, fields });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// POST /flyers/quick-generate  { template_id, lead_id? }
// AI writes the copy grounded in real lead/offer history when there is
// one, otherwise writes generic-but-professional placeholder copy for
// the tenant. Same maxTokens:2000 safe-value lesson as the rest of Cockpit.
router.post('/quick-generate', async (req, res) => {
  const tid = tenantId(req);
  const { template_id, lead_id } = req.body;
  if (!template_id) return res.status(400).json({ error: 'template_id is required' });

  const template = listTemplates().find((t) => t.id === template_id);
  if (!template) return res.status(400).json({ error: `Unknown template: ${template_id}` });

  const tenant = await db.prepare('SELECT name, theme_color FROM tenants WHERE id = ?').get(tid);

  let contextText = 'No specific lead — write generic, professional promotional copy suitable for any prospective student.';
  if (lead_id) {
    const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
    if (lead) {
      const offers = await db.prepare('SELECT * FROM offers WHERE tenant_id = ? AND lead_id = ? ORDER BY given_at DESC LIMIT 1').get(tid, lead_id);
      contextText = `Lead: ${lead.full_name}, stage: ${lead.stage}${offers ? `. Active offer: ${offers.offer_text}${offers.amount ? ` (₹${offers.amount})` : ''}` : ''}.`;
    }
  }

  const prompt = `Write short marketing copy for a promotional flyer, template type "${template.name}".
Fields needed: ${template.fields.filter((f) => f !== 'org_name' && f !== 'theme_color').join(', ')}.
Context: ${contextText}
Organization: ${tenant?.name || 'the consultancy'}.

Respond ONLY with valid JSON mapping each needed field name to short text
(keep each field concise — this is flyer copy, not paragraphs). Example
shape for an offer_announcement template:
{"headline": "...", "offer_text": "...", "subtext": "...", "contact_line": "..."}`;

  try {
    const aiFields = await generateJson(prompt, { maxTokens: 2000 });
    const fields = {
      org_name: tenant?.name || 'LeadFlow AI',
      theme_color: tenant?.theme_color || '#1B2A4A',
      ...aiFields,
    };
    const svg = renderTemplate(template_id, fields);
    const png = await getSharp()(Buffer.from(svg)).png().toBuffer();
    res.json({ image_data_uri: `data:image/png;base64,${png.toString('base64')}`, fields, ai_generated: true });
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// POST /flyers/save  { template_id, fields, lead_id?, ai_generated? }
// Persists the flyer and returns a real, permanent, shareable URL.
router.post('/save', async (req, res) => {
  const tid = tenantId(req);
  const { template_id, fields, lead_id, ai_generated } = req.body;
  if (!template_id || !fields) return res.status(400).json({ error: 'template_id and fields are required' });

  try {
    const svg = renderTemplate(template_id, fields);
    const png = await getSharp()(Buffer.from(svg)).png().toBuffer();
    const id = randomUUID();

    await db.prepare(`
      INSERT INTO flyers (id, tenant_id, lead_id, template_id, fields, png_base64, ai_generated)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(id, tid, lead_id || null, template_id, JSON.stringify(fields), png.toString('base64'), Boolean(ai_generated));

    res.status(201).json({ id, image_url: `${req.protocol}://${req.get('host')}/flyers/${id}/image` });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// GET /flyers/:id/image — serves the actual PNG bytes. This is a real,
// stable, publicly-viewable image URL (no auth — same reasoning as
// capture.js's public form: it needs to open in any browser, WhatsApp
// preview, or be uploaded into Canva without a login step).
router.get('/:id/image', async (req, res) => {
  const flyer = await db.prepare('SELECT png_base64 FROM flyers WHERE id = ?').get(req.params.id);
  if (!flyer) return res.status(404).send('Flyer not found');
  res.set('Content-Type', 'image/png');
  res.send(Buffer.from(flyer.png_base64, 'base64'));
});

// GET /flyers?lead_id=... — list saved flyers, optionally filtered to one lead
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  const rows = lead_id
    ? await db.prepare('SELECT id, template_id, lead_id, ai_generated, created_at FROM flyers WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC').all(tid, lead_id)
    : await db.prepare('SELECT id, template_id, lead_id, ai_generated, created_at FROM flyers WHERE tenant_id = ? ORDER BY created_at DESC LIMIT 50').all(tid);
  res.json(rows.map((r) => ({ ...r, image_url: `${req.protocol}://${req.get('host')}/flyers/${r.id}/image` })));
});

module.exports = router;
