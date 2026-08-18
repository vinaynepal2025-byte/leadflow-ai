// Qualification Agent -- Leads Ecosystem redesign, Phase 5.
//
// Scope: decide whether a lead has enough real signal to be marked
// QUALIFIED, and say exactly why. Never invents a verdict -- the
// qualified/not-qualified call is 100% deterministic, built on
// services/leadScoring.js's already-real, tenant-configurable scoring
// engine (LEADS_AUTOMATION_AUDIT.md section 4/10 names this exact
// pairing as the strongest existing seed for this agent). AI is used
// ONLY for color commentary (buying-intent read, risk flags) layered on
// top of the deterministic score -- if the AI call fails or isn't
// configured, the agent still produces a fully valid verdict from the
// score alone, same "never fabricate, degrade to deterministic" posture
// as services/smartTriage.js.
//
// Explicitly out of scope: this agent does not contact the lead, does
// not draft messages, and does not decide anything about counselling
// content -- only whether QUALIFIED is the right lifecycle_status.

const db = require('../../db');
const { scoreLead } = require('../leadScoring');
const { analyzeLead } = require('../aiAnalysis');
const { isValidTransition, computeAllowedNextStates, NEEDS_REVIEW } = require('../leadLifecycle');
const { safeAiJson, enqueueAgentAction } = require('./agentKit');

const AGENT_NAME = 'qualification';

async function analyze(tenantId, leadId) {
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tenantId, leadId);
  if (!lead) throw new Error(`Lead ${leadId} not found for this tenant`);

  const scoring = await scoreLead(db, tenantId, lead);

  const communications = await db.prepare(
    'SELECT * FROM communications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at ASC'
  ).all(tenantId, leadId);

  // aiAnalysis.analyzeLead already calls generateJson internally; wrap
  // it the same safe way agentKit.safeAiJson does rather than importing
  // a second AI path, so a failure here degrades exactly like every
  // other agent's AI call.
  let aiRead = null;
  try {
    aiRead = await analyzeLead(lead, communications);
  } catch (err) {
    console.warn(`[qualificationAgent] AI read failed, using score-only verdict: ${err.message}`);
  }

  const confidence = scoring.temperature === 'hot' ? 'high' : scoring.temperature === 'warm' ? 'medium' : 'low';

  // Deterministic verdict: hot always qualifies; warm qualifies only
  // with AI-confirmed high buying intent (when AI is available) or on
  // score alone once it clears the warm threshold if AI isn't
  // configured -- so the verdict never depends on AI being up, it's
  // only ever refined by it.
  const qualified = scoring.temperature === 'hot'
    || (scoring.temperature === 'warm' && (!aiRead || aiRead.buying_intent !== 'low'));

  const currentStatus = lead.lifecycle_status || NEEDS_REVIEW;
  const canMoveToQualified = isValidTransition(currentStatus, 'QUALIFIED');

  let recommendedAction = null;
  if (qualified && canMoveToQualified) {
    const topSignals = scoring.positive_signals.slice(0, 3).map((s) => s.reason).join('; ');
    recommendedAction = {
      tool_name: 'lead.update_lifecycle_status',
      tool_input: {
        lead_id: leadId,
        to_status: 'QUALIFIED',
        reason: `Qualification Agent: score ${scoring.score}/100 (${scoring.temperature}). Top signals: ${topSignals || 'none'}.`,
      },
    };
  }

  return {
    agent: AGENT_NAME,
    lead_id: leadId,
    score: scoring.score,
    temperature: scoring.temperature,
    confidence,
    explanation: scoring.signals,
    ai_read: aiRead, // null when AI unavailable/failed -- never fabricated
    qualified,
    lifecycle_status: currentStatus,
    allowed_next_lifecycle_states: computeAllowedNextStates(currentStatus),
    recommended_action: recommendedAction,
    blocked_reason: qualified && !canMoveToQualified
      ? `Lead qualifies by score, but ${currentStatus} cannot legally move to QUALIFIED (see allowed_next_lifecycle_states).`
      : null,
  };
}

// Explicitly separate from analyze() -- see agentKit.js's header comment.
// Only ever called today from an authenticated human action
// (routes/agents.js passes initiatedBy: 'manual'); nothing autonomous
// invokes this yet.
async function act(tenantId, leadId, { initiatedBy = 'manual', initiatedById } = {}) {
  const result = await analyze(tenantId, leadId);
  if (!result.recommended_action) {
    return { enqueued: false, reason: result.blocked_reason || 'Lead does not currently qualify.', analysis: result };
  }
  const job = await enqueueAgentAction({
    tenantId,
    agentName: AGENT_NAME,
    leadId,
    toolName: result.recommended_action.tool_name,
    toolInput: result.recommended_action.tool_input,
    initiatedBy,
    initiatedById,
  });
  return { enqueued: true, job, analysis: result };
}

module.exports = { AGENT_NAME, analyze, act };
