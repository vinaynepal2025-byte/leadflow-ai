// AI Agent endpoints -- Leads Ecosystem redesign, Phase 5. Every agent
// exposes the same two-verb shape:
//   POST /agents/:agent/:leadId/analyze — read-only, no side effects.
//   POST /agents/:agent/:leadId/act     — enqueues the analysis's
//     recommended_action (if any) through the durable orchestrator.
//     Always runs as initiated_by: 'manual' here, because the caller is
//     an authenticated human clicking a button -- see agentKit.js's
//     header comment for why nothing autonomous calls act() yet.
//
// The agent set itself lives in services/agents/registry.js, shared with
// services/agentScheduler.js (Phase 6's AUTO-mode scheduler) so both
// stay in sync about which agents exist.

const express = require('express');
const { AGENTS, AGENT_DESCRIPTIONS } = require('../services/agents/registry');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /agents — which agents exist, for the Automation Center screen.
router.get('/', (req, res) => {
  res.json(Object.keys(AGENTS).map((name) => ({ name, description: AGENT_DESCRIPTIONS[name] || null })));
});

router.post('/:agent/:leadId/analyze', async (req, res) => {
  const agent = AGENTS[req.params.agent];
  if (!agent) return res.status(404).json({ error: `Unknown agent "${req.params.agent}"` });

  try {
    const result = await agent.analyze(tenantId(req), req.params.leadId);
    res.json(result);
  } catch (err) {
    const status = /not found/i.test(err.message) ? 404 : 500;
    res.status(status).json({ error: err.message });
  }
});

router.post('/:agent/:leadId/act', async (req, res) => {
  const agent = AGENTS[req.params.agent];
  if (!agent) return res.status(404).json({ error: `Unknown agent "${req.params.agent}"` });

  try {
    const result = await agent.act(tenantId(req), req.params.leadId, {
      initiatedBy: 'manual',
      initiatedById: req.user?.id,
    });
    res.json(result);
  } catch (err) {
    const status = /not found/i.test(err.message) ? 404 : 500;
    res.status(status).json({ error: err.message });
  }
});

module.exports = router;
