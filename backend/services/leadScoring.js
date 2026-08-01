// Lead Scoring Engine — ranks every lead 0-100 by how likely they are to
// convert, using signals the app already collects.
//
// Deliberately rule-based and local: no API key, no per-lead cost, runs
// instantly over hundreds of leads, and — most importantly — explainable.
// A counselor can see exactly why someone scored 82, which an opaque model
// score can't give them.
//
// Every weight is tenant-configurable (see scoring_config table), because
// what predicts a conversion genuinely differs between consultancies.

const DEFAULT_WEIGHTS = {
  has_phone: 8,
  has_email: 4,
  has_parent_contact: 6,
  per_outreach: 2,
  max_outreach: 10,
  per_inbound_reply: 5,
  max_inbound_reply: 20,
  contact_within_3_days: 10,
  contact_within_7_days: 6,
  contact_within_14_days: 2,
  stale_over_21_days: -6,
  stale_over_30_days: -12,
  never_contacted: -10,
  per_meeting_attended: 8,
  max_meeting_attended: 16,
  campus_tour_completed: 12,
  per_no_show: -8,
  per_document: 4,
  max_documents: 12,
  has_paid: 20,
  per_application: 6,
  max_applications: 12,
  has_offer: 15,
  came_via_referral: 8,
  per_overdue_followup: -5,
  stage_Contacted: 5,
  stage_Counseling: 12,
  stage_Admission: 25,
  stage_Lost: -30,
};

const DEFAULT_THRESHOLDS = { hot: 70, warm: 40 };

async function loadConfig(db, tenantId) {
  const row = await db.prepare('SELECT weights, thresholds FROM scoring_config WHERE tenant_id = ?').get(tenantId);
  if (!row) return { weights: { ...DEFAULT_WEIGHTS }, thresholds: { ...DEFAULT_THRESHOLDS } };
  let saved = {};
  let savedThresholds = {};
  try {
    saved = JSON.parse(row.weights);
    savedThresholds = JSON.parse(row.thresholds);
  } catch {
    return { weights: { ...DEFAULT_WEIGHTS }, thresholds: { ...DEFAULT_THRESHOLDS } };
  }
  return {
    weights: { ...DEFAULT_WEIGHTS, ...saved },
    thresholds: { ...DEFAULT_THRESHOLDS, ...savedThresholds },
  };
}

async function scoreLead(db, tenantId, lead, config) {
  const cfg = config || await loadConfig(db, tenantId);
  const W = cfg.weights;
  const signals = [];
  let score = 0;

  const add = (points, reason) => {
    if (!points) return;
    score += points;
    signals.push({ points, reason });
  };

  if (lead.phone) add(W.has_phone, 'Phone number on file');
  if (lead.email) add(W.has_email, 'Email on file');
  if (lead.parent_name || lead.parent_phone) add(W.has_parent_contact, 'Parent/guardian contact captured');

  const comms = await db.prepare(
    'SELECT channel, direction, created_at FROM communications WHERE tenant_id = ? AND lead_id = ?'
  ).all(tenantId, lead.id);

  const inbound = comms.filter((c) => c.direction === 'inbound').length;
  const outbound = comms.filter((c) => c.direction === 'outbound').length;

  if (outbound > 0) add(Math.min(outbound * W.per_outreach, W.max_outreach), `${outbound} outreach attempt(s) logged`);
  if (inbound > 0) add(Math.min(inbound * W.per_inbound_reply, W.max_inbound_reply), `${inbound} reply/replies received from lead`);

  if (comms.length > 0) {
    const latest = comms.map((c) => new Date(c.created_at)).sort((a, b) => b - a)[0];
    const daysSince = Math.floor((Date.now() - latest.getTime()) / 86400000);
    if (daysSince <= 3) add(W.contact_within_3_days, 'Contact within last 3 days');
    else if (daysSince <= 7) add(W.contact_within_7_days, 'Contact within last week');
    else if (daysSince <= 14) add(W.contact_within_14_days, 'Contact within last 2 weeks');
    else if (daysSince > 30) add(W.stale_over_30_days, `No contact for ${daysSince} days — going cold`);
    else if (daysSince > 21) add(W.stale_over_21_days, `No contact for ${daysSince} days`);
  } else {
    add(W.never_contacted, 'Never contacted');
  }

  const meetings = await db.prepare(
    'SELECT meeting_type, status FROM meetings WHERE tenant_id = ? AND lead_id = ?'
  ).all(tenantId, lead.id);
  const completedMeetings = meetings.filter((m) => m.status === 'completed').length;
  const noShows = meetings.filter((m) => m.status === 'no-show').length;
  const tours = meetings.filter((m) => m.status === 'completed' && m.meeting_type.includes('Campus')).length;

  if (completedMeetings > 0) add(Math.min(completedMeetings * W.per_meeting_attended, W.max_meeting_attended), `${completedMeetings} meeting(s) attended`);
  if (tours > 0) add(W.campus_tour_completed, 'Completed a campus tour');
  if (noShows > 0) add(noShows * W.per_no_show, `${noShows} no-show(s)`);

  const docRow = await db.prepare(
    'SELECT COUNT(*) AS c FROM documents WHERE tenant_id = ? AND lead_id = ?'
  ).get(tenantId, lead.id);
  const docCount = docRow.c;
  if (docCount > 0) add(Math.min(docCount * W.per_document, W.max_documents), `${docCount} document(s) submitted`);

  const paidRow = await db.prepare(
    "SELECT COUNT(*) AS c FROM fee_payments WHERE tenant_id = ? AND lead_id = ? AND status = 'paid'"
  ).get(tenantId, lead.id);
  const paidCount = paidRow.c;
  if (paidCount > 0) add(W.has_paid, 'Has made a payment');

  const appRow = await db.prepare(
    'SELECT COUNT(*) AS c FROM admission_applications WHERE tenant_id = ? AND lead_id = ?'
  ).get(tenantId, lead.id);
  const appCount = appRow.c;
  if (appCount > 0) add(Math.min(appCount * W.per_application, W.max_applications), `${appCount} university application(s) started`);

  const offerRow = await db.prepare(
    "SELECT COUNT(*) AS c FROM admission_applications WHERE tenant_id = ? AND lead_id = ? AND application_status IN ('Offer','Accepted')"
  ).get(tenantId, lead.id);
  const offerCount = offerRow.c;
  if (offerCount > 0) add(W.has_offer, 'Holds an offer letter');

  if (lead.referred_by_lead_id || lead.referrer_name) add(W.came_via_referral, 'Came through a referral');

  const overdueRow = await db.prepare(
    "SELECT COUNT(*) AS c FROM reminders WHERE tenant_id = ? AND lead_id = ? AND status = 'pending' AND due_at < datetime('now')"
  ).get(tenantId, lead.id);
  const overdue = overdueRow.c;
  if (overdue > 0) add(overdue * W.per_overdue_followup, `${overdue} overdue follow-up(s) — we're the bottleneck`);

  const stageWeight = W[`stage_${lead.stage}`];
  if (stageWeight) add(stageWeight, `Stage: ${lead.stage}`);

  const finalScore = Math.max(0, Math.min(100, Math.round(score)));

  let temperature;
  if (finalScore >= cfg.thresholds.hot) temperature = 'hot';
  else if (finalScore >= cfg.thresholds.warm) temperature = 'warm';
  else temperature = 'cold';

  signals.sort((a, b) => Math.abs(b.points) - Math.abs(a.points));

  return {
    lead_id: lead.id,
    full_name: lead.full_name,
    stage: lead.stage,
    score: finalScore,
    temperature,
    signals,
    positive_signals: signals.filter((s) => s.points > 0),
    risk_signals: signals.filter((s) => s.points < 0),
  };
}

async function scoreAllLeads(db, tenantId) {
  const config = await loadConfig(db, tenantId);
  const leads = await db.prepare('SELECT * FROM leads WHERE tenant_id = ?').all(tenantId);
  const scored = [];
  for (const l of leads) {
    scored.push(await scoreLead(db, tenantId, l, config));
  }
  return scored.sort((a, b) => b.score - a.score);
}

module.exports = { scoreLead, scoreAllLeads, loadConfig, DEFAULT_WEIGHTS, DEFAULT_THRESHOLDS };
