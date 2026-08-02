const express = require('express');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /analytics/summary — everything the dashboard needs in one call
router.get('/summary', async (req, res) => {
  const tid = tenantId(req);

  const totalLeadsRow = await db.prepare('SELECT COUNT(*) AS c FROM leads WHERE tenant_id = ?').get(tid);
  const totalLeads = totalLeadsRow.c;

  const byStage = await db.prepare(
    'SELECT stage, COUNT(*) AS count FROM leads WHERE tenant_id = ? GROUP BY stage'
  ).all(tid);

  const bySource = await db.prepare(
    "SELECT COALESCE(source, 'Unknown') AS source, COUNT(*) AS count FROM leads WHERE tenant_id = ? GROUP BY source"
  ).all(tid);

  const pendingRemindersRow = await db.prepare(
    "SELECT COUNT(*) AS c FROM reminders WHERE tenant_id = ? AND status = 'pending'"
  ).get(tid);
  const pendingReminders = pendingRemindersRow.c;

  const overdueRemindersRow = await db.prepare(
    "SELECT COUNT(*) AS c FROM reminders WHERE tenant_id = ? AND status = 'pending' AND due_at < datetime('now')"
  ).get(tid);
  const overdueReminders = overdueRemindersRow.c;

  const communicationsTodayRow = await db.prepare(
    "SELECT COUNT(*) AS c FROM communications WHERE tenant_id = ? AND date(created_at) = date('now')"
  ).get(tid);
  const communicationsToday = communicationsTodayRow.c;

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
