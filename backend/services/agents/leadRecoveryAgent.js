// Lead Recovery Agent -- Leads Ecosystem redesign, Phase 5.
//
// Scope: the two mirror-image moves of the state machine's exit/recovery
// side (services/leadLifecycle.js's DORMANT/REACTIVATION states):
//   1. Notice an ACTIVE lead that's gone genuinely cold and mark it
//      DORMANT, so it stops cluttering active pipelines/follow-up
//      queues.
//   2. Notice a DORMANT/LOST/NOT_INTERESTED lead worth a deliberate
//      win-back attempt and propose REACTIVATION -- paired with a
//      reminder so a human actually makes that attempt, never a silent
//      status flip with nothing following up on it.
// Built on services/engagementTrend.js's cold/cooling detection --
// LEADS_AUTOMATION_AUDIT.md section 10 names this exact signal as the
// closest existing "detect at-risk/dormant" trigger condition in the
// codebase.
//
// Only ever proposes ONE of the two moves per analysis (a lead can't
// need both at once), and only when the state machine actually allows
// the transition -- never proposes an illegal move.

const db = require('../../db');
const { computeEngagementTrend } = require('../engagementTrend');
const { isValidTransition, computeAllowedNextStates, EXIT_STATES, NEEDS_REVIEW } = require('../leadLifecycle');
const { enqueueAgentAction } = require('./agentKit');

const AGENT_NAME = 'lead_recovery';
const COLD_DAYS_THRESHOLD = 30; // matches leadScoring.js's stale_over_30_days signal
const RECOVERY_COOLDOWN_DAYS = 14; // don't re-propose a win-back attempt more than once per this window

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

  const currentStatus = lead.lifecycle_status || NEEDS_REVIEW;
  const isActive = !EXIT_STATES.has(currentStatus) && currentStatus !== 'ADMISSION_CONFIRMED' && currentStatus !== 'REACTIVATION';

  let recommendedAction = null;
  let situation = 'no_action_needed';

  if (isActive && trend.trend === 'cold' && daysSinceContact !== null && daysSinceContact >= COLD_DAYS_THRESHOLD
      && isValidTransition(currentStatus, 'DORMANT')) {
    situation = 'going_dormant';
    recommendedAction = {
      tool_name: 'lead.update_lifecycle_status',
      tool_input: {
        lead_id: leadId,
        to_status: 'DORMANT',
        reason: `Lead Recovery Agent: no contact in ${daysSinceContact} days, engagement trend cold (${trend.reasoning}).`,
      },
    };
  } else if (EXIT_STATES.has(currentStatus) && isValidTransition(currentStatus, 'REACTIVATION')) {
    // Check the transition log for a recent recovery attempt so this
    // agent doesn't nag the same lost lead every single run.
    const recentAttempt = await db.prepare(`
      SELECT id FROM lead_lifecycle_transitions
      WHERE tenant_id = ? AND lead_id = ? AND to_status = 'REACTIVATION'
        AND created_at > now() - INTERVAL '${RECOVERY_COOLDOWN_DAYS} days'
      LIMIT 1
    `).get(tenantId, leadId);

    if (!recentAttempt) {
      situation = 'recovery_candidate';
      recommendedAction = {
        tool_name: 'lead.update_lifecycle_status',
        tool_input: {
          lead_id: leadId,
          to_status: 'REACTIVATION',
          reason: `Lead Recovery Agent: proposing a win-back attempt (currently ${currentStatus}, no attempt in the last ${RECOVERY_COOLDOWN_DAYS} days).`,
        },
      };
    } else {
      situation = 'recovery_attempt_already_in_progress';
    }
  }

  return {
    agent: AGENT_NAME,
    lead_id: leadId,
    lifecycle_status: currentStatus,
    days_since_contact: daysSinceContact,
    engagement_trend: trend.trend,
    engagement_reasoning: trend.reasoning,
    situation,
    allowed_next_lifecycle_states: computeAllowedNextStates(currentStatus),
    recommended_action: recommendedAction,
  };
}

// A REACTIVATION recommendation is always paired with a reminder so a
// human actually acts on the win-back attempt, not just a silent status
// flip. See agentKit.js's header comment for why act() only ever runs
// from an authenticated human action today (routes/agents.js passes
// initiatedBy: 'manual').
async function act(tenantId, leadId, { initiatedBy = 'manual', initiatedById } = {}) {
  const result = await analyze(tenantId, leadId);
  if (!result.recommended_action) {
    return { enqueued: false, reason: 'No recovery action needed for this lead right now.', analysis: result };
  }

  const statusJob = await enqueueAgentAction({
    tenantId,
    agentName: AGENT_NAME,
    leadId,
    toolName: result.recommended_action.tool_name,
    toolInput: result.recommended_action.tool_input,
    initiatedBy,
    initiatedById,
  });

  let reminderJob = null;
  if (result.situation === 'recovery_candidate') {
    const lead = await db.prepare('SELECT full_name FROM leads WHERE tenant_id = ? AND id = ?').get(tenantId, leadId);
    reminderJob = await enqueueAgentAction({
      tenantId,
      agentName: AGENT_NAME,
      leadId,
      toolName: 'reminder.create',
      toolInput: {
        lead_id: leadId,
        title: `Win-back attempt: reach out to ${lead?.full_name || 'this lead'} (marked for reactivation)`,
        due_at: new Date().toISOString(),
      },
      initiatedBy,
      initiatedById,
      dedupeSuffix: `reactivation-${new Date().toISOString().slice(0, 10)}`,
    });
  }

  return { enqueued: true, job: statusJob, reminder_job: reminderJob, analysis: result };
}

module.exports = { AGENT_NAME, analyze, act };
