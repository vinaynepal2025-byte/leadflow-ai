const express = require('express');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

const ALL_TYPES = ['communication', 'document', 'admission', 'fee'];

// pg has no custom type parser for TIMESTAMP columns (only bigint, see
// db.js), so created_at/updated_at come back as JS Date objects, not
// strings. Normalizing to an ISO string here -- rather than comparing
// e.at directly against the from/to query strings -- avoids a real bug:
// `Date >= "2026-08-01"` coerces the string to NaN and silently
// evaluates false for every row, which would make the date filter
// below discard everything instead of filtering it. Works whether the
// underlying value is already a Date or already a string.
function toIso(value) {
  return new Date(value).toISOString();
}

// GET /audit?lead_id=xxx&limit=50&types=communication,fee&from=2026-08-01&to=2026-08-31
// Everything in this app is already timestamped by design (communications,
// reminders, documents, fees, admissions) — Audit Center's job is to
// present that existing record as one unified, readable timeline, not to
// duplicate storage of what's already captured.
//
// types/from/to are new: previously this always returned every type,
// all-time, capped only by `limit` -- fine for a single lead's history,
// but unusable as a tenant-wide activity log once there's enough volume
// to actually need filtering. All three are optional and additive: no
// params behaves exactly as before.
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, from, to } = req.query;
  const limit = Math.min(parseInt(req.query.limit) || 50, 200);
  const requestedTypes = req.query.types
    ? String(req.query.types).split(',').map((t) => t.trim()).filter((t) => ALL_TYPES.includes(t))
    : ALL_TYPES;

  const leadFilter = lead_id ? 'AND lead_id = ?' : '';
  const leadParam = lead_id ? [lead_id] : [];

  const events = [];

  if (requestedTypes.includes('communication')) {
    for (const row of await db.prepare(
      `SELECT id, lead_id, channel, direction, body, created_by, created_at FROM communications WHERE tenant_id = ? ${leadFilter}`
    ).all(tid, ...leadParam)) {
      events.push({
        type: 'communication',
        lead_id: row.lead_id,
        summary: `${row.direction} ${row.channel}${row.created_by ? ` by ${row.created_by}` : ''}`,
        detail: row.body,
        at: toIso(row.created_at),
      });
    }
  }

  if (requestedTypes.includes('document')) {
    for (const row of await db.prepare(
      `SELECT id, lead_id, status, doc_type, created_at FROM documents WHERE tenant_id = ? ${leadFilter}`
    ).all(tid, ...leadParam)) {
      events.push({
        type: 'document',
        lead_id: row.lead_id,
        summary: `${row.doc_type} uploaded (${row.status})`,
        detail: null,
        at: toIso(row.created_at),
      });
    }
  }

  if (requestedTypes.includes('admission')) {
    for (const row of await db.prepare(
      `SELECT id, lead_id, application_status, institution_name, updated_at FROM admission_applications WHERE tenant_id = ? ${leadFilter}`
    ).all(tid, ...leadParam)) {
      events.push({
        type: 'admission',
        lead_id: row.lead_id,
        summary: `${row.institution_name}: ${row.application_status}`,
        detail: null,
        at: toIso(row.updated_at),
      });
    }
  }

  if (requestedTypes.includes('fee')) {
    for (const row of await db.prepare(
      `SELECT id, lead_id, status, fee_type, amount, created_at FROM fee_payments WHERE tenant_id = ? ${leadFilter}`
    ).all(tid, ...leadParam)) {
      events.push({
        type: 'fee',
        lead_id: row.lead_id,
        summary: `${row.fee_type}: ₹${row.amount} (${row.status})`,
        detail: null,
        at: toIso(row.created_at),
      });
    }
  }

  // Date-range filter applied post-merge rather than per-query -- the 4
  // source tables use different timestamp column names (created_at vs
  // updated_at), so filtering once here on the already-normalized `at`
  // string is simpler and less error-prone than repeating BETWEEN logic
  // with matching bind-param order across 4 differently-shaped queries.
  // Now safe: both sides of the comparison below are strings.
  let filtered = events;
  if (from) filtered = filtered.filter((e) => e.at >= from);
  if (to) filtered = filtered.filter((e) => e.at <= `${to}T23:59:59`);

  filtered.sort((a, b) => (a.at < b.at ? 1 : -1)); // newest first
  res.json(filtered.slice(0, limit));
});

module.exports = router;
