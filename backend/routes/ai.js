const express = require('express');
const db = require('../db');
const { analyzeLead } = require('../services/aiAnalysis');
const { activeProvider, activeModel, DEFAULT_MODELS, generateJson } = require('../services/aiProvider');

const router = express.Router();

// GET /ai/provider — which AI is active, and whether its key is set.
// Lets the app show "AI: Gemini (ready)" instead of failing silently.
router.get('/provider', async (req, res) => {
  const provider = activeProvider();
  const keyEnvVar = {
    claude: 'ANTHROPIC_API_KEY',
    gemini: 'GEMINI_API_KEY',
    openrouter: 'OPENROUTER_API_KEY',
  }[provider];
  res.json({
    provider,
    model: activeModel(),
    configured: Boolean(keyEnvVar && process.env[keyEnvVar]),
    available_providers: Object.keys(DEFAULT_MODELS),
  });
});

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// POST /ai/analyze-lead/:id — runs Claude over the lead's history
router.post('/analyze-lead/:id', async (req, res) => {
  const tid = tenantId(req);
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const communications = await db.prepare(
    'SELECT * FROM communications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at ASC'
  ).all(tid, req.params.id);

  try {
    const analysis = await analyzeLead(lead, communications);
    res.json(analysis);
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// POST /ai/generate-theme — turns a plain-language description (and,
// optionally, brand colors pulled from a logo) into a complete,
// ready-to-apply app theme. Portable by design: no db, no tenant
// coupling, no LeadFlow-specific knowledge -- just prompt in, theme
// JSON out, through the same generateJson() every AI feature uses.
// Drop this route + services/aiProvider.js into any other Express
// project to reuse it as-is.
const VALID_FONTS = ['spaceGroteskInter', 'playfairLato', 'poppinsRoboto', 'montserratOpenSans'];
const VALID_MODES = ['solid', 'glass', 'liquid', 'transparent', 'basic', 'cartoon', 'corporate'];
const HEX_RE = /^#?[0-9a-fA-F]{6}$/;

function asHex(v, fallback) {
  if (typeof v !== 'string' || !HEX_RE.test(v)) return fallback;
  return v.startsWith('#') ? v : `#${v}`;
}

router.post('/generate-theme', async (req, res) => {
  const { prompt, brandColors } = req.body || {};
  if (!prompt || typeof prompt !== 'string' || !prompt.trim()) {
    return res.status(400).json({ error: 'prompt is required, e.g. "premium and trustworthy for a medical admissions consultancy"' });
  }

  const brandHint = Array.isArray(brandColors) && brandColors.length
    ? `The institution's existing brand colors (from their logo) are: ${brandColors.join(', ')}. Anchor the palette around these if they fit the requested mood, otherwise you may override them.`
    : '';

  const instructionPrompt = `You are a UI design system generator for a mobile app. Given a description of the desired look, output ONLY a JSON object (no markdown fences, no commentary) with exactly these fields:
{
  "name": "string, 2-3 words, catchy theme name",
  "tagline": "string, max 6 words",
  "primary": "6-digit hex color, e.g. #1B2A4A",
  "accent": "6-digit hex color that contrasts well with primary",
  "font": "one of: spaceGroteskInter, playfairLato, poppinsRoboto, montserratOpenSans",
  "radius": number between 0 and 32 (corner roundness -- lower = sharper/corporate, higher = softer/playful),
  "dark": boolean,
  "styleMode": "one of: solid, glass, liquid, transparent, basic, cartoon, corporate",
  "glow": boolean,
  "glowColor": "6-digit hex color or null",
  "floating": boolean,
  "texture": boolean
}
Description: "${prompt.trim()}"
${brandHint}
Pick font/styleMode/radius that genuinely match the mood (e.g. a medical consultancy usually wants "corporate" or "solid" mode, montserratOpenSans or spaceGroteskInter, low-to-moderate radius, no glow -- vs. a trendy exam-prep coaching brand for teenagers might want "glass" or "cartoon", higher radius, maybe glow).`;

  try {
    const raw = await generateJson(instructionPrompt, { maxTokens: 1500 });

    const theme = {
      name: typeof raw.name === 'string' ? raw.name.slice(0, 40) : 'AI Theme',
      tagline: typeof raw.tagline === 'string' ? raw.tagline.slice(0, 60) : 'Generated for you',
      primary: asHex(raw.primary, '#1B2A4A'),
      accent: asHex(raw.accent, '#E8A33D'),
      font: VALID_FONTS.includes(raw.font) ? raw.font : 'spaceGroteskInter',
      radius: Number.isFinite(raw.radius) ? Math.max(0, Math.min(32, raw.radius)) : 16,
      dark: Boolean(raw.dark),
      styleMode: VALID_MODES.includes(raw.styleMode) ? raw.styleMode : 'solid',
      glow: Boolean(raw.glow),
      glowColor: raw.glow ? asHex(raw.glowColor, raw.accent) : null,
      floating: Boolean(raw.floating),
      texture: Boolean(raw.texture),
    };

    res.json(theme);
  } catch (err) {
    res.status(502).json({ error: 'Theme generation failed: ' + err.message });
  }
});

module.exports = router;
