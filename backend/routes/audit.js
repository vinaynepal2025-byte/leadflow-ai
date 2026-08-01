const express = require('express');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /audit?lead_id=xxx&limit=50
// Everything in this app is already timestamped by design (communications,
// reminders, documents, fees, admissions) — Audit Center's job is to
// present that existing record as one unified, readable timeline, not to
// duplicate storage of what's already captured.
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  const limit = Math.min(parseInt(req.query.limit) || 50, 200);

  const leadFilter = lead_id ? 'AND lead_id = ?' : '';
  const leadParam = lead_id ? [lead_id] : [];

  const events = [];

  for (const row of await db.prepare(
    `SELECT id, lead_id, channel, direction, body, created_by, created_at FROM communications WHERE tenant_id = ? ${leadFilter}`
  ).all(tid, ...leadParam)) {
    events.push({
      type: 'communication',
      lead_id: row.lead_id,
      summary: `${row.direction} ${row.channel}${row.created_by ? ` by ${row.created_by}` : ''}`,
      detail: row.body,
      at: row.created_at,
    });
  }

  for (const row of await db.prepare(
    `SELECT id, lead_id, status, doc_type, created_at FROM documents WHERE tenant_id = ? ${leadFilter}`
  ).all(tid, ...leadParam)) {
    events.push({
      type: 'document',
      lead_id: row.lead_id,
      summary: `${row.doc_type} uploaded (${row.status})`,
      detail: null,
      at: row.created_at,
    });
  }

  for (const row of await db.prepare(
    `SELECT id, lead_id, application_status, institution_name, updated_at FROM admission_applications WHERE tenant_id = ? ${leadFilter}`
  ).all(tid, ...leadParam)) {
    events.push({
      type: 'admission',
      lead_id: row.lead_id,
      summary: `${row.institution_name}: ${row.application_status}`,
      detail: null,
      at: row.updated_at,
    });
  }

  for (const row of await db.prepare(
    `SELECT id, lead_id, status, fee_type, amount, created_at FROM fee_payments WHERE tenant_id = ? ${leadFilter}`
  ).all(tid, ...leadParam)) {
    events.push({
      type: 'fee',
      lead_id: row.lead_id,
      summary: `${row.fee_type}: ₹${row.amount} (${row.status})`,
      detail: null,
      at: row.created_at,
    });
  }

  events.sort((a, b) => (a.at < b.at ? 1 : -1)); // newest first
  res.json(events.slice(0, limit));
});

module.exports = router;
