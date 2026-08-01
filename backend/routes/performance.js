const express = require('express');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

router.get('/', async (req, res) => {
  const tid = tenantId(req);

  const distinctRows = await db.prepare(
    "SELECT DISTINCT assigned_to FROM leads WHERE tenant_id = ? AND assigned_to IS NOT NULL"
  ).all(tid);
  const counselors = distinctRows.map((r) => r.assigned_to);

  const results = await Promise.all(counselors.map(async (counselor) => {
    const totalRow = await db.prepare(
      'SELECT COUNT(*) AS c FROM leads WHERE tenant_id = ? AND assigned_to = ?'
    ).get(tid, counselor);
    const totalLeads = totalRow.c;

    const admissionsRow = await db.prepare(
      "SELECT COUNT(*) AS c FROM leads WHERE tenant_id = ? AND assigned_to = ? AND stage = 'Admission'"
    ).get(tid, counselor);
    const admissions = admissionsRow.c;

    const lostRow = await db.prepare(
      "SELECT COUNT(*) AS c FROM leads WHERE tenant_id = ? AND assigned_to = ? AND stage = 'Lost'"
    ).get(tid, counselor);
    const lost = lostRow.c;

    const pendingRow = await db.prepare(`
      SELECT COUNT(*) AS c FROM reminders
      WHERE tenant_id = ? AND assigned_to = ? AND status = 'pending'
    `).get(tid, counselor);
    const pendingReminders = pendingRow.c;

    const commsRow = await db.prepare(`
      SELECT COUNT(*) AS c FROM communications
      WHERE tenant_id = ? AND created_by = ?
    `).get(tid, counselor);
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
