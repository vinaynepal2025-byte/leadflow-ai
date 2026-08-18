// Counselling Agent -- Leads Ecosystem redesign, Phase 5, tranche 4
// (final tranche).
//
// Scope: once a lead is qualified and ready for counselling, surface
// which colleges are actually a good fit for THIS tenant's own track
// record, and nudge toward starting applications when the data backs it.
// Built on predictions.js's already-real, deterministic, zero-AI
// college-fit ranking (historical offer rate from this tenant's own
// admission_applications outcomes, confidence bucketed by sample size --
// LEADS_AUTOMATION_AUDIT.md section 4 names this "a legitimate seed for
// a future Counselling Agent... currently entirely disconnected from any
// lead-facing recommendation flow"). Re-implemented here as a
// self-contained read-only query rather than importing route internals,
// same approach as every prior agent that reuses route-only logic.
//
// Explicitly out of scope: never creates an admission_applications row
// itself (that stays a human decision via admissions.js's existing
// POST), never advances lifecycle_status past what the Qualification
// Agent already handles -- only ever recommends a reminder to start
// applications, and only when the lead is actually ready for it.

const db = require('../../db');
const { enqueueAgentAction } = require('./agentKit');

const AGENT_NAME = 'counselling';
const READY_STATUSES = new Set(['QUALIFIED', 'COUNSELLING']);
const MIN_SAMPLE_FOR_CONFIDENCE = 3;
const TOP_N = 3;

async function rankColleges(tenantId) {
  const colleges = await db.prepare('SELECT * FROM colleges WHERE tenant_id = ?').all(tenantId);
  const ranked = [];
  for (const college of colleges) {
    const outcomes = await db.prepare(`
      SELECT application_status, COUNT(*) AS c
      FROM admission_applications
      WHERE tenant_id = ? AND institution_name = ?
      GROUP BY application_status
    `).all(tenantId, college.name);

    const offers = outcomes.filter((o) => ['Offer', 'Accepted'].includes(o.application_status)).reduce((s, o) => s + o.c, 0);
    const rejections = outcomes.filter((o) => o.application_status === 'Rejected').reduce((s, o) => s + o.c, 0);
    const totalDecided = offers + rejections;

    let historicalRate = null;
    let confidence = 'no data';
    if (totalDecided > 0) {
      historicalRate = Math.round((offers / totalDecided) * 100);
      confidence = totalDecided >= MIN_SAMPLE_FOR_CONFIDENCE ? 'moderate_or_higher' : 'low (few past cases)';
    }

    ranked.push({ college_id: college.id, college_name: college.name, country: college.country, historical_offer_rate_percent: historicalRate, confidence });
  }
  ranked.sort((a, b) => {
    if (a.historical_offer_rate_percent === null && b.historical_offer_rate_percent === null) return 0;
    if (a.historical_offer_rate_percent === null) return 1;
    if (b.historical_offer_rate_percent === null) return -1;
    return b.historical_offer_rate_percent - a.historical_offer_rate_percent;
  });
  return ranked;
}

async function analyze(tenantId, leadId) {
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tenantId, leadId);
  if (!lead) throw new Error(`Lead ${leadId} not found for this tenant`);

  const currentStatus = lead.lifecycle_status;
  if (!READY_STATUSES.has(currentStatus)) {
    return {
      agent: AGENT_NAME, lead_id: leadId, lifecycle_status: currentStatus,
      situation: 'not_yet_ready', top_colleges: [], recommended_action: null,
    };
  }

  const existingApplications = await db.prepare(
    'SELECT id FROM admission_applications WHERE tenant_id = ? AND lead_id = ?'
  ).all(tenantId, leadId);
  if (existingApplications.length > 0) {
    return {
      agent: AGENT_NAME, lead_id: leadId, lifecycle_status: currentStatus,
      situation: 'applications_in_progress', top_colleges: [], recommended_action: null,
    };
  }

  const ranked = await rankColleges(tenantId);
  if (ranked.length === 0) {
    return {
      agent: AGENT_NAME, lead_id: leadId, lifecycle_status: currentStatus,
      situation: 'no_college_data', top_colleges: [], recommended_action: null,
    };
  }

  const topColleges = ranked.slice(0, TOP_N);
  const wellSupported = topColleges.filter((c) => c.confidence === 'moderate_or_higher');

  let situation;
  let recommendedAction = null;
  if (wellSupported.length > 0) {
    situation = 'ready_to_start_applications';
    const names = wellSupported.map((c) => c.college_name).join(', ');
    recommendedAction = {
      tool_name: 'reminder.create',
      tool_input: {
        lead_id: leadId,
        title: `Start application(s) for ${lead.full_name} — best-fit colleges: ${names}`,
        due_at: new Date().toISOString(),
      },
    };
  } else {
    situation = 'insufficient_track_record';
  }

  return {
    agent: AGENT_NAME,
    lead_id: leadId,
    lifecycle_status: currentStatus,
    situation,
    top_colleges: topColleges,
    recommended_action: recommendedAction,
  };
}

// See agentKit.js's header comment -- act() only runs today from an
// authenticated human action (routes/agents.js passes
// initiatedBy: 'manual').
async function act(tenantId, leadId, { initiatedBy = 'manual', initiatedById } = {}) {
  const result = await analyze(tenantId, leadId);
  if (!result.recommended_action) {
    return { enqueued: false, reason: `No counselling action needed right now (${result.situation}).`, analysis: result };
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
