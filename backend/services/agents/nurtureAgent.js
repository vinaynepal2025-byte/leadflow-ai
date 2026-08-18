// Nurture Agent -- Leads Ecosystem redesign, Phase 5, tranche 2.
//
// Scope: keep top-of-funnel leads (NEW/CONTACT_PENDING/CONTACTED/
// ENGAGED -- not yet QUALIFIED) warm with value content on a slower
// cadence, distinct from the Follow-up Agent's "gone quiet, reconnect
// now" urgency. Built on cockpit.js's Content Library / content_sends
// tables (LEADS_AUTOMATION_AUDIT.md names cockpit.js's Content Library +
// Draft Engine as the seed for this agent, "currently manual-trigger
// only, no autonomous cadence") -- cockpit.js's own routes are left
// completely untouched; this agent reads the same tables independently.
//
// Same conservative posture as Follow-up: only ever recommends
// reminder.create (LOW risk). An AI-drafted message accompanying the
// suggested content is informational only, never auto-sent, and omitted
// (not guessed) when AI isn't available. Content SELECTION itself is
// deterministic (oldest not-yet-sent item first) so which content gets
// suggested never depends on AI being up.

const db = require('../../db');
const { safeAiJson, enqueueAgentAction } = require('./agentKit');

const AGENT_NAME = 'nurture';
const EARLY_FUNNEL_STATUSES = new Set(['NEW', 'CONTACT_PENDING', 'CONTACTED', 'ENGAGED']);
const NURTURE_CADENCE_DAYS = 5;

async function analyze(tenantId, leadId) {
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tenantId, leadId);
  if (!lead) throw new Error(`Lead ${leadId} not found for this tenant`);

  const currentStatus = lead.lifecycle_status;
  if (!EARLY_FUNNEL_STATUSES.has(currentStatus)) {
    return {
      agent: AGENT_NAME, lead_id: leadId, lifecycle_status: currentStatus,
      situation: 'not_applicable', recommended_action: null,
    };
  }

  const library = await db.prepare('SELECT * FROM content_library WHERE tenant_id = ? AND active = true ORDER BY created_at ASC').all(tenantId);
  const sends = await db.prepare('SELECT content_id, sent_at FROM content_sends WHERE tenant_id = ? AND lead_id = ? ORDER BY sent_at DESC').all(tenantId, leadId);
  const alreadySentIds = new Set(sends.map((s) => s.content_id));
  const availableContent = library.filter((c) => !alreadySentIds.has(c.id));

  const daysSinceLastNurture = sends.length > 0
    ? Math.floor((Date.now() - new Date(sends[0].sent_at).getTime()) / 86400000)
    : null;

  const dueForNurture = (daysSinceLastNurture === null || daysSinceLastNurture >= NURTURE_CADENCE_DAYS) && availableContent.length > 0;

  let situation;
  let recommendedAction = null;
  let suggestedContent = null;
  let suggestedMessage = null;

  if (!dueForNurture && availableContent.length === 0) {
    situation = 'no_content_available';
  } else if (!dueForNurture) {
    situation = 'recently_nurtured';
  } else {
    situation = 'due_for_nurture';
    const pick = availableContent[0]; // deterministic: oldest unsent item, never AI-picked
    suggestedContent = { id: pick.id, title: pick.title, content_type: pick.content_type };

    const ai = await safeAiJson(`You are drafting a short, warm nurture message for an early-stage
admissions lead who hasn't disengaged, just isn't ready to move forward yet.
Introduce this one piece of content naturally -- do not sound like a template.

Lead: ${lead.full_name}, stage: ${lead.stage}
Content to introduce: "${pick.title}" (${pick.content_type})

Respond ONLY with valid JSON, no other text, in exactly this shape:
{
  "recommended_channel": "whatsapp | email",
  "message_draft": "the actual message text, ready to review and send",
  "reasoning": "1 sentence on why this content fits where this lead is"
}`, { maxTokens: 600 });
    suggestedMessage = ai; // null if AI unavailable -- never fabricated

    recommendedAction = {
      tool_name: 'reminder.create',
      tool_input: {
        lead_id: leadId,
        title: `Send nurture content to ${lead.full_name}: "${pick.title}"`,
        due_at: new Date().toISOString(),
      },
    };
  }

  return {
    agent: AGENT_NAME,
    lead_id: leadId,
    lifecycle_status: currentStatus,
    days_since_last_nurture: daysSinceLastNurture,
    available_content_count: availableContent.length,
    situation,
    suggested_content: suggestedContent,
    suggested_message: suggestedMessage,
    recommended_action: recommendedAction,
  };
}

// See agentKit.js's header comment -- act() only runs today from an
// authenticated human action (routes/agents.js passes
// initiatedBy: 'manual').
async function act(tenantId, leadId, { initiatedBy = 'manual', initiatedById } = {}) {
  const result = await analyze(tenantId, leadId);
  if (!result.recommended_action) {
    return { enqueued: false, reason: `No nurture action needed right now (${result.situation}).`, analysis: result };
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
