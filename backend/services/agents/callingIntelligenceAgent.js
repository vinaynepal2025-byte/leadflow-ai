// Calling Intelligence Agent -- Leads Ecosystem redesign, Phase 5,
// tranche 3.
//
// Scope: notice when a lead needs another call attempt and say when to
// try it. Built entirely on calls.js's already-real call_logs analytics
// (connect rate, best-hour-to-call derived from when THIS lead has
// actually answered, falling back to tenant-wide data on too little
// history) -- re-implemented here as a small, self-contained read-only
// query rather than importing route internals, same approach as
// documentAgent.js's checklist cross-reference. LEADS_AUTOMATION_AUDIT.md
// section 4 is explicit that "no AI-during-call capability exists (no
// transcription/live-assist)" -- consistent with that, this agent makes
// NO AI call at all; it is 100% deterministic, same design philosophy as
// leadScoring.js/engagementTrend.js/predictions.js.
//
// Explicitly out of scope: does not place calls, does not transcribe or
// summarize a call (that's voiceNotes.js's existing job), does not
// change lifecycle_status.

const db = require('../../db');
const { EXIT_STATES, TERMINAL_STATUSES } = require('../leadLifecycle');
const { enqueueAgentAction } = require('./agentKit');

const AGENT_NAME = 'calling_intelligence';
const CONNECTED_OUTCOMES = ['connected', 'interested', 'not_interested', 'callback_requested'];
const MIN_SAMPLE_FOR_LEAD_BEST_HOUR = 3;
const EARLY_FUNNEL_STATUSES = new Set(['NEW', 'CONTACT_PENDING', 'CONTACTED']);

function formatHour(h) {
  const suffix = h < 12 ? 'AM' : 'PM';
  const display = h % 12 === 0 ? 12 : h % 12;
  return `${display} ${suffix}`;
}

// Same bucket-by-hour logic as calls.js's GET /calls/best-time, applied
// to whichever row set (lead-scoped or tenant-wide) the caller passes in.
function bestHourFromRows(rows) {
  const buckets = {};
  for (const r of rows) {
    const hour = parseInt(String(r.created_at).substring(11, 13), 10);
    if (Number.isNaN(hour)) continue;
    buckets[hour] = (buckets[hour] || 0) + 1;
  }
  const ranked = Object.entries(buckets).map(([hour, count]) => ({ hour: Number(hour), count })).sort((a, b) => b.count - a.count);
  if (ranked.length === 0) return null;
  return { hour: ranked[0].hour, label: `${formatHour(ranked[0].hour)} – ${formatHour((ranked[0].hour + 1) % 24)}` };
}

async function analyze(tenantId, leadId) {
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tenantId, leadId);
  if (!lead) throw new Error(`Lead ${leadId} not found for this tenant`);

  const calls = await db.prepare(
    'SELECT outcome, duration_seconds, created_at, follow_up_at FROM call_logs WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC'
  ).all(tenantId, leadId);

  const totalAttempts = calls.length;
  const connectedCalls = calls.filter((c) => CONNECTED_OUTCOMES.includes(c.outcome));
  const connectRate = totalAttempts === 0 ? null : Math.round((connectedCalls.length / totalAttempts) * 100);

  let bestTime = bestHourFromRows(connectedCalls);
  let bestTimeScope = 'lead';
  if (connectedCalls.length < MIN_SAMPLE_FOR_LEAD_BEST_HOUR) {
    const tenantConnected = await db.prepare(
      `SELECT created_at FROM call_logs WHERE tenant_id = ? AND outcome IN (${CONNECTED_OUTCOMES.map(() => '?').join(',')})`
    ).all(tenantId, ...CONNECTED_OUTCOMES);
    if (tenantConnected.length >= MIN_SAMPLE_FOR_LEAD_BEST_HOUR) {
      bestTime = bestHourFromRows(tenantConnected);
      bestTimeScope = 'tenant';
    } else {
      bestTime = null;
      bestTimeScope = 'none';
    }
  }

  // calls is ordered newest-first, so calls[0] is the most recent
  // attempt. If IT scheduled a follow-up (calls.js auto-schedules one for
  // no_answer/busy/switched_off/callback_requested) and that follow-up is
  // now due, no newer call has happened since by definition -- the
  // promised retry never actually took place.
  // A lead that's NOT_INTERESTED/LOST/DORMANT/ADMISSION_CONFIRMED doesn't
  // need another call attempt -- it's closed. Without this guard, a
  // dead lead with a years-old overdue follow_up_at, or one that was
  // never called before being marked NOT_INTERESTED some other way,
  // would get "Call X" reminders forever under AUTO mode.
  const isClosed = EXIT_STATES.has(lead.lifecycle_status) || TERMINAL_STATUSES.has(lead.lifecycle_status);

  const mostRecent = calls[0];
  const overdueFollowUp = Boolean(mostRecent?.follow_up_at && new Date(mostRecent.follow_up_at) <= new Date());
  const neverCalled = totalAttempts === 0 && EARLY_FUNNEL_STATUSES.has(lead.lifecycle_status);
  const zeroConnectsAfterSeveralAttempts = totalAttempts >= 3 && connectedCalls.length === 0;

  const needsCallAttempt = !isClosed && (Boolean(overdueFollowUp) || neverCalled || zeroConnectsAfterSeveralAttempts);

  let recommendedAction = null;
  let situation = 'no_action_needed';
  if (needsCallAttempt) {
    situation = neverCalled ? 'never_called' : zeroConnectsAfterSeveralAttempts ? 'not_connecting' : 'follow_up_overdue';
    const timeHint = bestTime ? ` — best time to try: ${bestTime.label}${bestTimeScope === 'tenant' ? ' (tenant-wide pattern, not enough history for this lead yet)' : ''}` : '';
    recommendedAction = {
      tool_name: 'reminder.create',
      tool_input: {
        lead_id: leadId,
        title: `Call ${lead.full_name}${timeHint}`,
        due_at: new Date().toISOString(),
      },
    };
  }

  return {
    agent: AGENT_NAME,
    lead_id: leadId,
    total_attempts: totalAttempts,
    connected_count: connectedCalls.length,
    connect_rate: connectRate,
    best_time: bestTime,
    best_time_scope: bestTimeScope,
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
    return { enqueued: false, reason: 'No call attempt needed for this lead right now.', analysis: result };
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
