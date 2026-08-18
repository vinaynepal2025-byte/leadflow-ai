// AI Agent endpoints -- Leads Ecosystem redesign, Phase 5, Tranche 1
// (Qualification, Follow-up, Lead Recovery). Every agent exposes the
// same two-verb shape:
//   POST /agents/:agent/:leadId/analyze — read-only, no side effects.
//   POST /agents/:agent/:leadId/act     — enqueues the analysis's
//     recommended_action (if any) through the durable orchestrator.
//     Always runs as initiated_by: 'manual' here, because the caller is
//     an authenticated human clicking a button -- see agentKit.js's
//     header comment for why nothing autonomous calls act() yet.
//
// More agents land the same way in later tranches; this file is meant
// to grow, not be replaced.

const express = require('express');
const qualificationAgent = require('../services/agents/qualificationAgent');
const followUpAgent = require('../services/agents/followUpAgent');
const leadRecoveryAgent = require('../services/agents/leadRecoveryAgent');
const intakeAgent = require('../services/agents/intakeAgent');
const documentAgent = require('../services/agents/documentAgent');
const nurtureAgent = require('../services/agents/nurtureAgent');
const callingIntelligenceAgent = require('../services/agents/callingIntelligenceAgent');
const paymentCommitmentAgent = require('../services/agents/paymentCommitmentAgent');
const counsellingAgent = require('../services/agents/counsellingAgent');
const admissionAgent = require('../services/agents/admissionAgent');

const router = express.Router();

const AGENTS = {
  [qualificationAgent.AGENT_NAME]: qualificationAgent,
  [followUpAgent.AGENT_NAME]: followUpAgent,
  [leadRecoveryAgent.AGENT_NAME]: leadRecoveryAgent,
  [intakeAgent.AGENT_NAME]: intakeAgent,
  [documentAgent.AGENT_NAME]: documentAgent,
  [nurtureAgent.AGENT_NAME]: nurtureAgent,
  [callingIntelligenceAgent.AGENT_NAME]: callingIntelligenceAgent,
  [paymentCommitmentAgent.AGENT_NAME]: paymentCommitmentAgent,
  [counsellingAgent.AGENT_NAME]: counsellingAgent,
  [admissionAgent.AGENT_NAME]: admissionAgent,
};

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /agents — which agents exist, for a future Automation Center screen.
router.get('/', (req, res) => {
  res.json(Object.keys(AGENTS).map((name) => ({ name })));
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
