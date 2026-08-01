const express = require('express');
const db = require('../db');
const { analyzeLead } = require('../services/aiAnalysis');
const { activeProvider, activeModel, DEFAULT_MODELS } = require('../services/aiProvider');

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

module.exports = router;
