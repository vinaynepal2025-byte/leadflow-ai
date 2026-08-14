const express = require('express');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /performance?from=2026-08-01&to=2026-08-31
// from/to are new and optional: no params behaves exactly as before
// (all-time counts). When given, total_leads/admissions/lost scope to
// leads CREATED in that window, and communications_logged scopes to
// messages logged in that window -- so "this month's performance"
// actually means something instead of the same lifetime total every
// time. pending_reminders deliberately stays un-scoped either way: it's
// a current-state count ("what's overdue right now"), not a historical
// one, and a reminder due outside the selected window would be
// confusing to hide.
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { from, to } = req.query;
  const toEnd = to ? `${to}T23:59:59` : null;

  const distinctRows = await db.prepare(
    "SELECT DISTINCT assigned_to FROM leads WHERE tenant_id = ? AND assigned_to IS NOT NULL"
  ).all(tid);
  const counselors = distinctRows.map((r) => r.assigned_to);

  const leadDateFilter = from && to ? 'AND created_at BETWEEN ? AND ?' : '';
  const leadDateParams = from && to ? [from, toEnd] : [];
  const commsDateFilter = from && to ? 'AND created_at BETWEEN ? AND ?' : '';
  const commsDateParams = from && to ? [from, toEnd] : [];

  const results = await Promise.all(counselors.map(async (counselor) => {
    const totalRow = await db.prepare(
      `SELECT COUNT(*) AS c FROM leads WHERE tenant_id = ? AND assigned_to = ? ${leadDateFilter}`
    ).get(tid, counselor, ...leadDateParams);
    const totalLeads = totalRow.c;

    const admissionsRow = await db.prepare(
      `SELECT COUNT(*) AS c FROM leads WHERE tenant_id = ? AND assigned_to = ? AND stage = 'Admission' ${leadDateFilter}`
    ).get(tid, counselor, ...leadDateParams);
    const admissions = admissionsRow.c;

    const lostRow = await db.prepare(
      `SELECT COUNT(*) AS c FROM leads WHERE tenant_id = ? AND assigned_to = ? AND stage = 'Lost' ${leadDateFilter}`
    ).get(tid, counselor, ...leadDateParams);
    const lost = lostRow.c;

    const pendingRow = await db.prepare(`
      SELECT COUNT(*) AS c FROM reminders
      WHERE tenant_id = ? AND assigned_to = ? AND status = 'pending'
    `).get(tid, counselor);
    const pendingReminders = pendingRow.c;

    const commsRow = await db.prepare(`
      SELECT COUNT(*) AS c FROM communications
      WHERE tenant_id = ? AND created_by = ? ${commsDateFilter}
    `).get(tid, counselor, ...commsDateParams);
    const communicationsLogged = commsRow.c;

    return {
      counselor,
      total_leads: totalLeads,
      admissions,
      lost,
      conversion_rate_percent: totalLeads > 0 ? Math.round((admissions / totalLeads) * 1000) / 10 : 0,
      pending_reminders: pendingReminders,
      communications_logged: communicationsLogged,
    };
  }));

  results.sort((a, b) => b.conversion_rate_percent - a.conversion_rate_percent);
  res.json(results);
});

module.exports = router;
