const express = require('express');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /analytics/summary — everything the dashboard needs in one call
router.get('/summary', (req, res) => {
  const tid = tenantId(req);

  const totalLeads = db.prepare('SELECT COUNT(*) AS c FROM leads WHERE tenant_id = ?').get(tid).c;

  const byStage = db.prepare(
    'SELECT stage, COUNT(*) AS count FROM leads WHERE tenant_id = ? GROUP BY stage'
  ).all(tid);

  const bySource = db.prepare(
    "SELECT COALESCE(source, 'Unknown') AS source, COUNT(*) AS count FROM leads WHERE tenant_id = ? GROUP BY source"
  ).all(tid);

  const pendingReminders = db.prepare(
    "SELECT COUNT(*) AS c FROM reminders WHERE tenant_id = ? AND status = 'pending'"
  ).get(tid).c;

  const overdueReminders = db.prepare(
    "SELECT COUNT(*) AS c FROM reminders WHERE tenant_id = ? AND status = 'pending' AND due_at < datetime('now')"
  ).get(tid).c;

  const communicationsToday = db.prepare(
    "SELECT COUNT(*) AS c FROM communications WHERE tenant_id = ? AND date(created_at) = date('now')"
  ).get(tid).c;

  // Simple conversion funnel: how many leads have ever reached each stage
  // is out of scope for v1 (needs stage-history tracking, not just current
  // stage) — this summary reflects *current* pipeline distribution only.
  const admissions = byStage.find((s) => s.stage === 'Admission')?.count || 0;
  const conversionRate = totalLeads > 0 ? Math.round((admissions / totalLeads) * 1000) / 10 : 0;

  res.json({
    total_leads: totalLeads,
    by_stage: byStage,
    by_source: bySource,
    pending_reminders: pendingReminders,
    overdue_reminders: overdueReminders,
    communications_today: communicationsToday,
    conversion_rate_percent: conversionRate,
  });
});

module.exports = router;
