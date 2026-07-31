const express = require('express');
const db = require('../db');
const { scoreLead, scoreAllLeads, loadConfig, DEFAULT_WEIGHTS, DEFAULT_THRESHOLDS } = require('../services/leadScoring');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

/// Human labels + grouping so Settings can render this without hardcoding
/// a duplicate list that would drift out of sync with the engine.
const WEIGHT_META = {
  has_phone: { label: 'Phone number on file', group: 'Contact Info' },
  has_email: { label: 'Email on file', group: 'Contact Info' },
  has_parent_contact: { label: 'Parent/guardian contact captured', group: 'Contact Info' },
  per_outreach: { label: 'Per outreach attempt we made', group: 'Engagement' },
  max_outreach: { label: 'Max points from outreach', group: 'Engagement' },
  per_inbound_reply: { label: 'Per reply received from lead', group: 'Engagement' },
  max_inbound_reply: { label: 'Max points from replies', group: 'Engagement' },
  contact_within_3_days: { label: 'Contacted within 3 days', group: 'Recency' },
  contact_within_7_days: { label: 'Contacted within a week', group: 'Recency' },
  contact_within_14_days: { label: 'Contacted within 2 weeks', group: 'Recency' },
  stale_over_21_days: { label: 'No contact 21+ days', group: 'Recency' },
  stale_over_30_days: { label: 'No contact 30+ days', group: 'Recency' },
  never_contacted: { label: 'Never contacted at all', group: 'Recency' },
  per_meeting_attended: { label: 'Per meeting attended', group: 'Meetings' },
  max_meeting_attended: { label: 'Max points from meetings', group: 'Meetings' },
  campus_tour_completed: { label: 'Completed a campus tour', group: 'Meetings' },
  per_no_show: { label: 'Per no-show', group: 'Meetings' },
  per_document: { label: 'Per document submitted', group: 'Commitment' },
  max_documents: { label: 'Max points from documents', group: 'Commitment' },
  has_paid: { label: 'Has made a payment', group: 'Commitment' },
  per_application: { label: 'Per university application', group: 'Commitment' },
  max_applications: { label: 'Max points from applications', group: 'Commitment' },
  has_offer: { label: 'Holds an offer letter', group: 'Commitment' },
  came_via_referral: { label: 'Came through a referral', group: 'Source' },
  per_overdue_followup: { label: 'Per overdue follow-up (our delay)', group: 'Our Responsiveness' },
  stage_Contacted: { label: 'Stage: Contacted', group: 'Pipeline Stage' },
  stage_Counseling: { label: 'Stage: Counseling', group: 'Pipeline Stage' },
  stage_Admission: { label: 'Stage: Admission', group: 'Pipeline Stage' },
  stage_Lost: { label: 'Stage: Lost', group: 'Pipeline Stage' },
};

// GET /scoring/config — current weights + labels so Settings can build the UI
router.get('/config', (req, res) => {
  const tid = tenantId(req);
  const cfg = loadConfig(db, tid);
  const isCustomized = Boolean(db.prepare('SELECT tenant_id FROM scoring_config WHERE tenant_id = ?').get(tid));

  res.json({
    customized: isCustomized,
    thresholds: cfg.thresholds,
    default_thresholds: DEFAULT_THRESHOLDS,
    weights: Object.entries(cfg.weights).map(([key, value]) => ({
      key,
      value,
      default_value: DEFAULT_WEIGHTS[key],
      label: WEIGHT_META[key]?.label || key,
      group: WEIGHT_META[key]?.group || 'Other',
    })),
  });
});

// PUT /scoring/config  { weights: {key: value}, thresholds: {hot, warm} }
// Partial updates are fine — anything omitted keeps its current value.
router.put('/config', (req, res) => {
  const tid = tenantId(req);
  const current = loadConfig(db, tid);

  const newWeights = { ...current.weights };
  if (req.body.weights && typeof req.body.weights === 'object') {
    for (const [key, value] of Object.entries(req.body.weights)) {
      if (!(key in DEFAULT_WEIGHTS)) {
        return res.status(400).json({ error: `Unknown scoring signal "${key}"` });
      }
      if (typeof value !== 'number' || !Number.isFinite(value)) {
        return res.status(400).json({ error: `Weight for "${key}" must be a number` });
      }
      if (value < -100 || value > 100) {
        return res.status(400).json({ error: `Weight for "${key}" must be between -100 and 100` });
      }
      newWeights[key] = value;
    }
  }

  const newThresholds = { ...current.thresholds };
  if (req.body.thresholds && typeof req.body.thresholds === 'object') {
    for (const key of ['hot', 'warm']) {
      if (req.body.thresholds[key] !== undefined) {
        const v = req.body.thresholds[key];
        if (typeof v !== 'number' || v < 0 || v > 100) {
          return res.status(400).json({ error: `Threshold "${key}" must be a number between 0 and 100` });
        }
        newThresholds[key] = v;
      }
    }
    if (newThresholds.warm >= newThresholds.hot) {
      return res.status(400).json({ error: 'The "warm" threshold must be lower than "hot"' });
    }
  }

  db.prepare(`
    INSERT INTO scoring_config (tenant_id, weights, thresholds, updated_at)
    VALUES (?, ?, ?, datetime('now'))
    ON CONFLICT(tenant_id) DO UPDATE SET weights = excluded.weights, thresholds = excluded.thresholds, updated_at = datetime('now')
  `).run(tid, JSON.stringify(newWeights), JSON.stringify(newThresholds));

  res.json({ weights: newWeights, thresholds: newThresholds });
});

// POST /scoring/config/reset
router.post('/config/reset', (req, res) => {
  const tid = tenantId(req);
  db.prepare('DELETE FROM scoring_config WHERE tenant_id = ?').run(tid);
  res.json({ weights: DEFAULT_WEIGHTS, thresholds: DEFAULT_THRESHOLDS, reset: true });
});

// POST /scoring/config/preview — see how a proposed change would reshuffle
// the pipeline BEFORE saving it. Changing scoring blind is how a team
// accidentally buries the leads they were about to close.
router.post('/config/preview', (req, res) => {
  const tid = tenantId(req);
  const current = loadConfig(db, tid);
  const proposed = {
    weights: { ...current.weights, ...(req.body.weights || {}) },
    thresholds: { ...current.thresholds, ...(req.body.thresholds || {}) },
  };

  const leads = db.prepare('SELECT * FROM leads WHERE tenant_id = ? LIMIT 200').all(tid);
  const before = leads.map((l) => scoreLead(db, tid, l, current));
  const after = leads.map((l) => scoreLead(db, tid, l, proposed));

  const changes = before.map((b, i) => ({
    lead_id: b.lead_id,
    full_name: b.full_name,
    score_before: b.score,
    score_after: after[i].score,
    temperature_before: b.temperature,
    temperature_after: after[i].temperature,
  })).filter((c) => c.score_before !== c.score_after)
    .sort((a, b) => Math.abs(b.score_after - b.score_before) - Math.abs(a.score_after - a.score_before));

  const countBy = (list, t) => list.filter((s) => s.temperature === t).length;

  res.json({
    affected_count: changes.length,
    biggest_changes: changes.slice(0, 15),
    distribution_before: { hot: countBy(before, 'hot'), warm: countBy(before, 'warm'), cold: countBy(before, 'cold') },
    distribution_after: { hot: countBy(after, 'hot'), warm: countBy(after, 'warm'), cold: countBy(after, 'cold') },
  });
});

// GET /scoring/lead/:id — one lead's score with full explanation
router.get('/lead/:id', (req, res) => {
  const tid = tenantId(req);
  const lead = db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });
  res.json(scoreLead(db, tid, lead));
});

// GET /scoring/ranked?temperature=hot&limit=20
// The whole pipeline, best-first. This is the view a counselor should
// start their day on rather than a chronological list.
router.get('/ranked', (req, res) => {
  const tid = tenantId(req);
  const { temperature } = req.query;
  const limit = Math.min(parseInt(req.query.limit) || 50, 200);

  let scored = scoreAllLeads(db, tid);
  if (temperature) scored = scored.filter((s) => s.temperature === temperature);
  res.json(scored.slice(0, limit));
});

// GET /scoring/today — the actual work queue: who to call, in what order,
// and why. Combines high-intent leads with ones actively slipping away.
router.get('/today', (req, res) => {
  const tid = tenantId(req);
  const scored = scoreAllLeads(db, tid);

  const active = scored.filter((s) => !['Closed', 'Lost'].includes(s.stage));

  // Hot and warm leads worth pushing today
  const priority = active.filter((s) => s.temperature === 'hot').slice(0, 10);
  const priorityIds = new Set(priority.map((p) => p.lead_id));

  // Leads sliding backwards. Deliberately excludes anyone already in
  // priority_calls — showing the same person in two lists makes the
  // queue noisier, not more useful. Threshold is low because a lead
  // decaying from 30 is exactly who gets quietly abandoned.
  const atRisk = active
    .filter((s) => !priorityIds.has(s.lead_id) && s.risk_signals.length > 0 && s.score >= 15)
    .sort((a, b) => {
      const riskA = a.risk_signals.reduce((sum, r) => sum + Math.abs(r.points), 0);
      const riskB = b.risk_signals.reduce((sum, r) => sum + Math.abs(r.points), 0);
      return riskB - riskA;
    })
    .slice(0, 10);

  // Never-contacted leads, oldest-first — the silent leak in most pipelines
  const untouched = db.prepare(`
    SELECT l.id, l.full_name, l.created_at FROM leads l
    WHERE l.tenant_id = ? AND l.stage = 'New'
      AND NOT EXISTS (SELECT 1 FROM communications c WHERE c.lead_id = l.id)
    ORDER BY l.created_at ASC LIMIT 10
  `).all(tid);

  res.json({
    priority_calls: priority,
    at_risk: atRisk,
    never_contacted: untouched,
    summary: {
      hot: active.filter((s) => s.temperature === 'hot').length,
      warm: active.filter((s) => s.temperature === 'warm').length,
      cold: active.filter((s) => s.temperature === 'cold').length,
      never_contacted: untouched.length,
    },
  });
});

module.exports = router;
