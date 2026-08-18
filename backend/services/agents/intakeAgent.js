// Intake Agent -- Leads Ecosystem redesign, Phase 5, tranche 2.
//
// Scope: the moment a lead enters the system -- flag likely duplicates,
// notice missing baseline contact info, and (if the lead is clean and
// complete) move it from NEW to CONTACT_PENDING so it's visible as
// something needing a first touch. Built on
// services/duplicateDetection.js's already-real fuzzy phone/name
// matching (LEADS_AUTOMATION_AUDIT.md section 4 names leadAdsWebhook.js/
// capture.js/leadsImport*.js as real ingestion with "zero agent framing"
// -- this agent is that framing, not a new ingestion path).
//
// Explicitly does NOT auto-merge duplicates -- same rule
// duplicateDetection.js's own header comment states: "a human decides."
// This agent only ever recommends a notification flagging the
// possibility.

const db = require('../../db');
const { findDuplicates } = require('../duplicateDetection');
const { isValidTransition, NEEDS_REVIEW } = require('../leadLifecycle');
const { enqueueAgentAction } = require('./agentKit');

const AGENT_NAME = 'intake';

async function analyze(tenantId, leadId) {
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tenantId, leadId);
  if (!lead) throw new Error(`Lead ${leadId} not found for this tenant`);

  const rawDuplicates = await findDuplicates(db, tenantId, { full_name: lead.full_name, phone: lead.phone });
  const duplicates = rawDuplicates.filter((d) => d.lead_id !== leadId);

  const hasMinimumContact = Boolean(lead.phone || lead.email);
  const currentStatus = lead.lifecycle_status || NEEDS_REVIEW;

  let situation;
  let recommendedAction = null;

  if (duplicates.length > 0) {
    situation = 'possible_duplicate';
    const top = duplicates[0];
    recommendedAction = {
      tool_name: 'notification.create',
      tool_input: {
        title: `Possible duplicate: ${lead.full_name}`,
        body: `Matches existing lead "${top.full_name}" (${top.reasons.join(', ')}). Review before treating as a new lead.`,
        link_type: 'lead',
        link_id: leadId,
      },
    };
  } else if (!hasMinimumContact) {
    situation = 'missing_contact_info';
    recommendedAction = {
      tool_name: 'reminder.create',
      tool_input: {
        lead_id: leadId,
        title: `Get a phone or email for ${lead.full_name} — intake is incomplete without one`,
        due_at: new Date().toISOString(),
      },
    };
  } else if (currentStatus === 'NEW' && isValidTransition(currentStatus, 'CONTACT_PENDING')) {
    situation = 'ready_for_contact';
    recommendedAction = {
      tool_name: 'lead.update_lifecycle_status',
      tool_input: {
        lead_id: leadId,
        to_status: 'CONTACT_PENDING',
        reason: 'Intake Agent: no duplicate risk, has contact info, ready for first outreach.',
      },
    };
  } else {
    situation = 'no_action_needed';
  }

  return {
    agent: AGENT_NAME,
    lead_id: leadId,
    lifecycle_status: currentStatus,
    has_minimum_contact: hasMinimumContact,
    duplicate_candidates: duplicates,
    situation,
    recommended_action: recommendedAction,
  };
}

// See agentKit.js's header comment -- act() only runs today from an
// authenticated human action (routes/agents.js passes
// initiatedBy: 'manual').
async function act(tenantId, leadId, { initiatedBy = 'manual', initiatedById } = {}) {
  const result = await analyze(tenantId, leadId);
  if (!result.recommended_action) {
    return { enqueued: false, reason: 'No intake action needed for this lead.', analysis: result };
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
