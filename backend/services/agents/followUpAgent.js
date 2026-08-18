// Follow-up Agent -- Leads Ecosystem redesign, Phase 5.
//
// Scope: notice when a lead has gone quiet and needs a nudge, and say
// what to do about it. Built on services/engagementTrend.js (the same
// deterministic silent-churn detector cockpit.js's existing Next Best
// Action already uses) -- LEADS_AUTOMATION_AUDIT.md names cockpit.js's
// Next Best Action / Send Queue as the single best-matched existing seed
// for this agent. cockpit.js itself is left completely untouched; this
// agent builds its own equivalent analysis independently rather than
// importing route-file internals.
//
// Deliberately conservative about WHAT it recommends doing: the only
// action this agent will propose enqueueing is reminder.create (LOW
// risk, internal-only -- creates a task for a human, sends nothing to
// the lead). It also surfaces an AI-drafted suggested_message purely as
// INFORMATION for a human to review and send themselves via the
// existing cockpit/WhatsApp flows -- it is never auto-sent, and is
// omitted entirely (not guessed) if AI isn't configured.

const db = require('../../db');
const { computeEngagementTrend } = require('../engagementTrend');
const { safeAiJson, enqueueAgentAction } = require('./agentKit');

const AGENT_NAME = 'follow_up';
const STALE_DAYS_THRESHOLD = 3; // matches cockpit.js's send-queue window

async function analyze(tenantId, leadId) {
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tenantId, leadId);
  if (!lead) throw new Error(`Lead ${leadId} not found for this tenant`);

  const communications = await db.prepare(
    'SELECT * FROM communications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at ASC'
  ).all(tenantId, leadId);

  const trend = computeEngagementTrend(communications);

  const daysSinceContact = lead.last_contacted_at
    ? Math.floor((Date.now() - new Date(lead.last_contacted_at).getTime()) / 86400000)
    : null;

  const isStale = daysSinceContact === null || daysSinceContact >= STALE_DAYS_THRESHOLD;
  const needsFollowUp = isStale || trend.trend === 'cooling' || trend.trend === 'cold';

  let suggestedMessage = null;
  if (needsFollowUp) {
    const historyText = communications
      .map((c) => `[${c.created_at}] ${c.direction} ${c.channel}: ${c.body || '(no text)'}`)
      .join('\n') || '(no interactions logged yet)';

    const ai = await safeAiJson(`You are a senior admissions counselor's assistant. This lead needs a
follow-up nudge. Suggest ONE short, warm, specific message a counselor could
send -- grounded in their actual history below, never generic.

Lead: ${lead.full_name}, stage: ${lead.stage}
Days since last contact: ${daysSinceContact ?? 'never contacted'}
Engagement trend (rule-based): ${trend.trend} -- ${trend.reasoning}

Interaction history:
${historyText}

Respond ONLY with valid JSON, no other text, in exactly this shape:
{
  "recommended_channel": "whatsapp | call | email",
  "message_draft": "the actual message text, ready to review and send",
  "reasoning": "1 sentence on why this is the right move"
}`, { maxTokens: 800 });
    suggestedMessage = ai; // null if AI unavailable -- never fabricated
  }

  const recommendedAction = needsFollowUp ? {
    tool_name: 'reminder.create',
    tool_input: {
      lead_id: leadId,
      title: `Follow up with ${lead.full_name} — ${daysSinceContact === null ? 'never contacted' : `no contact in ${daysSinceContact} days`}`,
      due_at: new Date().toISOString(),
    },
  } : null;

  return {
    agent: AGENT_NAME,
    lead_id: leadId,
    days_since_contact: daysSinceContact,
    engagement_trend: trend.trend,
    engagement_reasoning: trend.reasoning,
    needs_follow_up: needsFollowUp,
    suggested_message: suggestedMessage, // informational only, never auto-sent
    recommended_action: recommendedAction,
  };
}

// See agentKit.js's header comment -- act() only ever runs today from an
// authenticated human action (routes/agents.js passes
// initiatedBy: 'manual'). The recommended action here is always
// reminder.create (LOW risk), so it executes immediately either way;
// nothing about act() itself sends a message to the lead.
async function act(tenantId, leadId, { initiatedBy = 'manual', initiatedById } = {}) {
  const result = await analyze(tenantId, leadId);
  if (!result.recommended_action) {
    return { enqueued: false, reason: 'This lead does not currently need a follow-up.', analysis: result };
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
