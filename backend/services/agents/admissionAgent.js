// Admission Agent -- Leads Ecosystem redesign, Phase 5, tranche 4 (final
// tranche of the spec's 10 agents).
//
// Scope: watch a lead's admission_applications for the two things that
// actually need a human's attention: an offer that's arrived but hasn't
// been reflected in the lead's lifecycle_status yet, and an application
// that's gone quiet with the institution for too long. Built on
// admissions.js's application_status tracking, which
// LEADS_AUTOMATION_AUDIT.md section 4 describes plainly: "data model
// exists; purely CRUD today, no agent logic at all." This agent is that
// logic layer.
//
// The OFFER transition is the one place in this tranche an agent
// recommends a lifecycle_status change on a signal weaker than
// Qualification's own score -- but the signal here is about as
// unambiguous as they come: admissions.js's application_status is
// already constrained to a fixed enum (APPLICATION_STAGES), and 'Offer'/
// 'Accepted' both mean an institution has already said yes. Recommending
// anything past OFFER (COMMITMENT/PAYMENT_PENDING) would require a
// genuine student decision this agent has no way to know about, so it
// deliberately stops there.

const db = require('../../db');
const { isValidTransition, NEEDS_REVIEW } = require('../leadLifecycle');
const { enqueueAgentAction } = require('./agentKit');

const AGENT_NAME = 'admission';
const OFFER_STATUSES = new Set(['Offer', 'Accepted']);
const IN_PROGRESS_STATUSES = new Set(['Submitted', 'Under Review']);
const STALE_DAYS_THRESHOLD = 21;

async function analyze(tenantId, leadId) {
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tenantId, leadId);
  if (!lead) throw new Error(`Lead ${leadId} not found for this tenant`);

  const applications = await db.prepare(
    'SELECT * FROM admission_applications WHERE tenant_id = ? AND lead_id = ? ORDER BY updated_at DESC'
  ).all(tenantId, leadId);

  // A lead created before the lifecycle-status backfill migration ran
  // (or by any ingestion path that doesn't set it -- see
  // LEADS_AUTOMATION_AUDIT.md-driven fixes) has NULL here, not
  // NEEDS_REVIEW. isValidTransition(null, 'OFFER') is always false, so
  // without this fallback a fresh lead with a real offer on file would
  // be silently misreported as offer_received_but_status_blocked
  // instead of getting the recommendation it actually qualifies for --
  // same fallback every other agent that reads lifecycle_status uses.
  const currentStatus = lead.lifecycle_status || NEEDS_REVIEW;
  const offerApplications = applications.filter((a) => OFFER_STATUSES.has(a.application_status));

  let situation = 'no_action_needed';
  let recommendedAction = null;

  if (offerApplications.length > 0 && isValidTransition(currentStatus, 'OFFER')) {
    situation = 'offer_received';
    const names = offerApplications.map((a) => a.institution_name).join(', ');
    recommendedAction = {
      tool_name: 'lead.update_lifecycle_status',
      tool_input: {
        lead_id: leadId,
        to_status: 'OFFER',
        reason: `Admission Agent: offer/acceptance on file from ${names}.`,
      },
    };
  } else {
    const staleApplications = applications.filter((a) => {
      if (!IN_PROGRESS_STATUSES.has(a.application_status)) return false;
      const daysSinceUpdate = Math.floor((Date.now() - new Date(a.updated_at).getTime()) / 86400000);
      return daysSinceUpdate >= STALE_DAYS_THRESHOLD;
    });

    if (staleApplications.length > 0) {
      situation = 'application_stalled';
      const names = staleApplications.map((a) => a.institution_name).join(', ');
      recommendedAction = {
        tool_name: 'reminder.create',
        tool_input: {
          lead_id: leadId,
          title: `Check application status with institution for ${lead.full_name}: ${names} (no update in ${STALE_DAYS_THRESHOLD}+ days)`,
          due_at: new Date().toISOString(),
        },
      };
    } else if (offerApplications.length > 0) {
      // An offer exists but the state machine won't allow OFFER from here
      // (e.g. the lead is already past it, or in an exit state) -- surface
      // the fact without proposing an illegal transition.
      situation = 'offer_received_but_status_blocked';
    }
  }

  return {
    agent: AGENT_NAME,
    lead_id: leadId,
    lifecycle_status: currentStatus,
    application_count: applications.length,
    offer_count: offerApplications.length,
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
    return { enqueued: false, reason: `No admission action needed right now (${result.situation}).`, analysis: result };
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
