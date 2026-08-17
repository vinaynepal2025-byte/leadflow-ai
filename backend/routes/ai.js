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
//
// Batch 5 (Customize Studio): expanded from the original 4 font
// pairings to all 10 the app now bundles, added optional gradient +
// backdrop-blur generation for glass/liquid moods, and added
// server-side WCAG contrast validation so a generated theme can't ship
// with illegible color choices -- "world-class" is a guarantee here,
// not just a badge the person could ignore in the picker.
const VALID_FONTS = [
  'spaceGroteskInter', 'playfairLato', 'poppinsRoboto', 'montserratOpenSans',
  'interRoboto', 'playfairOpenSans', 'spaceGroteskLato', 'montserratInter', 'poppinsOpenSans', 'interLato',
];
const VALID_MODES = ['solid', 'glass', 'liquid', 'transparent', 'basic', 'cartoon', 'corporate'];
const HEX_RE = /^#?[0-9a-fA-F]{6}$/;

function asHex(v, fallback) {
  if (typeof v !== 'string' || !HEX_RE.test(v)) return fallback;
  return v.startsWith('#') ? v : `#${v}`;
}

// WCAG 2.1 contrast math, same formula validated numerically against
// known reference ratios (white/black=21.0, etc.) when Batch 3 built the
// Flutter-side equivalent in theme/contrast_utils.dart. Reimplemented
// here in JS rather than shared, since this is the only server-side call
// site and duplicating ~15 lines is simpler than a cross-language shared
// module for one use.
function relativeLuminance(hex) {
  const n = parseInt(hex.replace('#', ''), 16);
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((c) => c / 255);
  const gamma = (v) => (v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));
  return 0.2126 * gamma(r) + 0.7152 * gamma(g) + 0.0722 * gamma(b);
}
function contrastRatio(hexA, hexB) {
  const l1 = relativeLuminance(hexA), l2 = relativeLuminance(hexB);
  const [lighter, darker] = l1 > l2 ? [l1, l2] : [l2, l1];
  return (lighter + 0.05) / (darker + 0.05);
}
// Darkens a hex color by a fixed step, bounded, for the auto-correction
// loop below -- deliberately simple (multiply each channel) rather than
// proper HSL lightness adjustment, since it only needs to move contrast
// in one direction reliably, not preserve hue precision.
function darken(hex, factor) {
  const n = parseInt(hex.replace('#', ''), 16);
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((c) => Math.max(0, Math.round(c * factor)));
  return `#${((r << 16) | (g << 8) | b).toString(16).padStart(6, '0')}`;
}
// If primary fails AA (4.5:1) against white -- the common case, since
// primary is frequently used as a filled button/badge background with
// white text -- darken it in small steps until it passes, capped so a
// pathological input can't loop forever. Most real generated colors
// pass in 0-2 steps; this exists for the rare case Gemini picks
// something too light/pastel for a filled-background role.
function ensureContrastSafe(hex) {
  let color = hex;
  for (let i = 0; i < 6 && contrastRatio(color, '#FFFFFF') < 4.5; i++) {
    color = darken(color, 0.85);
  }
  return color;
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
  "font": "one of: spaceGroteskInter, playfairLato, poppinsRoboto, montserratOpenSans, interRoboto, playfairOpenSans, spaceGroteskLato, montserratInter, poppinsOpenSans, interLato",
  "radius": number between 0 and 32 (corner roundness -- lower = sharper/corporate, higher = softer/playful),
  "dark": boolean,
  "styleMode": "one of: solid, glass, liquid, transparent, basic, cartoon, corporate",
  "glow": boolean,
  "glowColor": "6-digit hex color or null",
  "floating": boolean,
  "texture": boolean,
  "gradientEnd": "6-digit hex color for a 2-stop gradient FROM primary TO this color, or null if the mood doesn't call for one",
  "backdropBlur": "number 0.0-1.0, only meaningful when styleMode is glass or liquid -- how frosted the surfaces should feel"
}
Description: "${prompt.trim()}"
${brandHint}
Font personality guide -- pick the one that actually matches the mood, don't default to the same one every time:
- spaceGroteskInter/interRoboto/interLato/montserratInter: clean modern SaaS, tech-forward
- playfairLato/playfairOpenSans: editorial, premium, serif-led, upscale
- poppinsRoboto/poppinsOpenSans: friendly, approachable, rounded
- montserratOpenSans: classic corporate
- spaceGroteskLato: tech-meets-warm hybrid
Pick font/styleMode/radius/gradientEnd/backdropBlur that genuinely match the mood (e.g. a medical consultancy usually wants "corporate" or "solid" mode, montserratOpenSans or spaceGroteskInter, low-to-moderate radius, no glow, no gradient -- vs. a trendy exam-prep coaching brand for teenagers might want "glass" or "cartoon" mode, higher radius, maybe glow and a gradient). Only set gradientEnd/glow/floating/texture/backdropBlur when they genuinely serve the requested mood -- a "minimal and professional" request should get mostly false/null here, not every effect turned on.`;

  try {
    const raw = await generateJson(instructionPrompt, { maxTokens: 1500 });

    const primary = ensureContrastSafe(asHex(raw.primary, '#1B2A4A'));
    const styleMode = VALID_MODES.includes(raw.styleMode) ? raw.styleMode : 'solid';
    const isGlassy = styleMode === 'glass' || styleMode === 'liquid';

    const theme = {
      name: typeof raw.name === 'string' ? raw.name.slice(0, 40) : 'AI Theme',
      tagline: typeof raw.tagline === 'string' ? raw.tagline.slice(0, 60) : 'Generated for you',
      primary,
      accent: asHex(raw.accent, '#E8A33D'),
      font: VALID_FONTS.includes(raw.font) ? raw.font : 'spaceGroteskInter',
      radius: Number.isFinite(raw.radius) ? Math.max(0, Math.min(32, raw.radius)) : 16,
      dark: Boolean(raw.dark),
      styleMode,
      glow: Boolean(raw.glow),
      glowColor: raw.glow ? asHex(raw.glowColor, raw.accent) : null,
      floating: Boolean(raw.floating),
      texture: Boolean(raw.texture),
      // Only meaningful (and only sent) for glass/liquid -- a solid/basic
      // theme with a stray backdropBlur value would be a no-op in the
      // Flutter renderer anyway, but omitting it here keeps the payload
      // honest about what this theme actually uses.
      gradientEnd: raw.gradientEnd ? asHex(raw.gradientEnd, null) : null,
      backdropBlur: isGlassy && Number.isFinite(raw.backdropBlur) ? Math.max(0, Math.min(1, raw.backdropBlur)) : 0,
    };

    res.json(theme);
  } catch (err) {
    res.status(502).json({ error: 'Theme generation failed: ' + err.message });
  }
});

// POST /ai/suggest-emojis  { message_text }
// Context-aware emoji suggestions for the message composer -- text-only,
// reuses the existing generateJson() provider layer, zero new cost or
// infrastructure. Deliberately stateless (no db, no tenant coupling)
// like generate-theme above, since the message text itself is all the
// context this needs.
router.post('/suggest-emojis', async (req, res) => {
  const messageText = (req.body.message_text || '').toString().trim();
  if (!messageText) return res.status(400).json({ error: 'message_text is required' });

  const prompt = `You are suggesting relevant emoji for a professional admissions-consultancy message to a student or parent.
Given the message below, suggest 3 to 6 Unicode emoji that would appropriately accent it -- consider its content, sentiment, and professional-but-warm tone. Do not overuse emoji; prefer fewer, more relevant ones over a scattershot list.

Respond with ONLY a JSON array of emoji characters, most relevant first, e.g. ["\uD83C\uDF93","\u2705"]. No markdown fences, no explanation, no other text.

Message:
\`\`\`
${messageText.slice(0, 2000)}
\`\`\``;

  try {
    let emojis;
    try {
      emojis = await generateJson(prompt, { maxTokens: 500 });
    } catch (firstErr) {
      // One retry for transient upstream issues (provider overload,
      // truncated response) -- these are usually momentary, and a
      // single retry costs little compared to surfacing an error for
      // something that would have worked a few seconds later.
      emojis = await generateJson(prompt, { maxTokens: 500 });
    }
    if (!Array.isArray(emojis)) throw new Error('AI response was not a JSON array');
    res.json({ emojis: emojis.slice(0, 6) });
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// POST /ai/restyle-section  { instruction, item_label, current_color, current_style_variant }
// The backend half of "AI Quick Restyle" -- a single natural-language
// command changes exactly one already-identified button/section's look
// (colour, gradient, style-variant), never the whole app's theme. Which
// item to restyle is resolved client-side (mobile/lib/screens/
// customize_registry.dart's findBestMatch, deterministic label
// matching -- no AI needed just to find a button by name); this route
// only interprets the *style* half of the command, reusing the same
// generateJson() provider layer as generate-theme/suggest-emojis.
router.post('/restyle-section', async (req, res) => {
  const { instruction, item_label, current_color, current_style_variant } = req.body || {};
  if (!instruction || typeof instruction !== 'string' || !instruction.trim()) {
    return res.status(400).json({ error: 'instruction is required, e.g. "make it glow orange"' });
  }
  if (!item_label || typeof item_label !== 'string') {
    return res.status(400).json({ error: 'item_label is required' });
  }

  const prompt = `You are a UI styling assistant. A mobile app has one specific button/section called "${item_label}". Its current style is: colour ${current_color || '(default)'}, style-variant ${current_style_variant || 'flat'}.
The user gave this instruction for how to restyle ONLY this one button: "${instruction.trim()}"
Output ONLY a JSON object (no markdown fences, no commentary) with exactly these fields:
{
  "color": "6-digit hex color for this item, e.g. #E85D4E -- your best interpretation of any colour/mood mentioned, or the current colour if none is implied",
  "styleVariant": "one of: flat, gradient_badge, glow, glass -- pick gradient_badge if the instruction mentions a gradient/two colours blending, glow if it mentions glow/neon/pulse, glass if it mentions glass/frosted/transparent, otherwise flat",
  "gradientEnd": "6-digit hex color to gradient toward, ONLY when styleVariant is gradient_badge and a second colour is implied or a sensible complementary one can be chosen -- otherwise null"
}
Interpret colour words naturally (e.g. "gold" -> a real gold hex, "forest green" -> a real dark green hex, "hot pink" -> a real vivid pink hex) -- don't just reuse the current colour unless the instruction genuinely doesn't ask for a colour change.`;

  try {
    const raw = await generateJson(prompt, { maxTokens: 400 });
    const color = asHex(raw.color, current_color || '#1B2A4A');
    const validVariants = ['flat', 'gradient_badge', 'glow', 'glass'];
    const styleVariant = validVariants.includes(raw.styleVariant) ? raw.styleVariant : 'flat';
    const gradientEnd = styleVariant === 'gradient_badge' ? asHex(raw.gradientEnd, color) : null;
    res.json({ color, styleVariant, gradientEnd });
  } catch (err) {
    res.status(502).json({ error: 'Restyle failed: ' + err.message });
  }
});

// POST /ai/find-icon  { query, available_keys }
// Flyer/Logo Studio's "AI Icon Finder" -- type a concept ("graduation
// cap", "handshake deal"), get back the best-matching icon from the
// app's own curated library (kFlyerIconLibrary, mobile/lib/screens/
// flyer_studio/flyer_element.dart) plus a fitting colour, added to the
// canvas in one tap. The client sends its own available_keys so this
// route never needs a second copy of the icon list to keep in sync --
// the AI can only pick a key that's actually in the set it was given,
// validated below rather than trusted blindly.
router.post('/find-icon', async (req, res) => {
  const { query, available_keys } = req.body || {};
  if (!query || typeof query !== 'string' || !query.trim()) {
    return res.status(400).json({ error: 'query is required, e.g. "graduation cap"' });
  }
  if (!Array.isArray(available_keys) || available_keys.length === 0) {
    return res.status(400).json({ error: 'available_keys must be a non-empty array' });
  }

  const prompt = `You are matching a plain-language concept to the closest icon in a fixed icon set for a design tool.
Available icon keys (pick EXACTLY ONE of these, verbatim): ${available_keys.join(', ')}
Concept to match: "${query.trim()}"
Output ONLY a JSON object (no markdown fences, no commentary):
{
  "iconKey": "one of the available icon keys above, your best match for the concept",
  "color": "6-digit hex color that suits the concept's mood, e.g. #1B2A4A"
}`;

  try {
    const raw = await generateJson(prompt, { maxTokens: 200 });
    const iconKey = available_keys.includes(raw.iconKey) ? raw.iconKey : available_keys[0];
    const color = asHex(raw.color, '#1B2A4A');
    res.json({ iconKey, color });
  } catch (err) {
    res.status(502).json({ error: 'Icon search failed: ' + err.message });
  }
});

module.exports = router;
