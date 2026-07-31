const express = require('express');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /performance — breakdown by counselor (assigned_to on leads)
// v1 metrics: leads assigned, admissions closed, conversion %, pending
// follow-ups owned, communications logged. Response-time metrics need
// timestamped first-contact tracking not yet in the schema — noted as a
// clear next step rather than faked with placeholder numbers.
router.get('/', (req, res) => {
  const tid = tenantId(req);

  const counselors = db.prepare(
    "SELECT DISTINCT assigned_to FROM leads WHERE tenant_id = ? AND assigned_to IS NOT NULL"
  ).all(tid).map((r) => r.assigned_to);

  const results = counselors.map((counselor) => {
    const totalLeads = db.prepare(
      'SELECT COUNT(*) AS c FROM leads WHERE tenant_id = ? AND assigned_to = ?'
    ).get(tid, counselor).c;

    const admissions = db.prepare(
      "SELECT COUNT(*) AS c FROM leads WHERE tenant_id = ? AND assigned_to = ? AND stage = 'Admission'"
    ).get(tid, counselor).c;

    const lost = db.prepare(
      "SELECT COUNT(*) AS c FROM leads WHERE tenant_id = ? AND assigned_to = ? AND stage = 'Lost'"
    ).get(tid, counselor).c;

    const pendingReminders = db.prepare(`
      SELECT COUNT(*) AS c FROM reminders
      WHERE tenant_id = ? AND assigned_to = ? AND status = 'pending'
    `).get(tid, counselor).c;

    const communicationsLogged = db.prepare(`
      SELECT COUNT(*) AS c FROM communications
      WHERE tenant_id = ? AND created_by = ?
    `).get(tid, counselor).c;

    return {
      counselor,
      total_leads: totalLeads,
      admissions,
      lost,
      conversion_rate_percent: totalLeads > 0 ? Math.round((admissions / totalLeads) * 1000) / 10 : 0,
      pending_reminders: pendingReminders,
      communications_logged: communicationsLogged,
    };
  });

  // Highest conversion first — the leaderboard view
  results.sort((a, b) => b.conversion_rate_percent - a.conversion_rate_percent);
  res.json(results);
});

module.exports = router;
