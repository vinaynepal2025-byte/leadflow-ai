// Shared registry of every Phase 5 agent -- the single source of truth
// both routes/agents.js (human-triggered analyze/act) and
// services/agentScheduler.js (Phase 6's AUTO-mode scheduler) import from,
// so the two never drift out of sync about which agents exist.

const qualificationAgent = require('./qualificationAgent');
const followUpAgent = require('./followUpAgent');
const leadRecoveryAgent = require('./leadRecoveryAgent');
const intakeAgent = require('./intakeAgent');
const documentAgent = require('./documentAgent');
const nurtureAgent = require('./nurtureAgent');
const callingIntelligenceAgent = require('./callingIntelligenceAgent');
const paymentCommitmentAgent = require('./paymentCommitmentAgent');
const counsellingAgent = require('./counsellingAgent');
const admissionAgent = require('./admissionAgent');

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

// Short, human-readable descriptions for the Automation Center UI --
// kept here rather than on each agent module so agent files stay focused
// on logic, not display copy.
const AGENT_DESCRIPTIONS = {
  intake: 'Flags possible duplicates, checks for missing contact info, and readies a new lead for first contact.',
  qualification: 'Scores a lead deterministically and recommends moving it to Qualified when the signals support it.',
  calling_intelligence: 'Flags leads needing a call attempt and suggests the best time to try, based on real call history.',
  follow_up: 'Notices a lead has gone quiet and suggests a follow-up, with an optional AI-drafted message to review.',
  nurture: "Keeps early-stage leads warm with your content library on a slower cadence than Follow-up's.",
  counselling: 'Surfaces which colleges are the best statistical fit and nudges toward starting applications.',
  document: 'Flags missing, pending, or rejected documents, cross-referenced against visa checklists where relevant.',
  payment_commitment: 'Flags overdue fee installments once fees.js\'s own due-date reminder has already passed.',
  admission: 'Notices an arrived offer or a stalled application with no institution response in 21+ days.',
  lead_recovery: 'Marks a genuinely cold lead dormant, or proposes a deliberate win-back attempt for a lost one.',
};

module.exports = { AGENTS, AGENT_DESCRIPTIONS };
