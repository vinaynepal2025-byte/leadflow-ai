const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { fireEvent } = require('../services/automationEngine');
const { findDuplicates } = require('../services/duplicateDetection');

const router = express.Router();

// Every route is tenant-scoped — no cross-tenant leakage (multi-tenant obligation).
// tenant_id comes from the auth token in production; for now it's a header
// so the API is testable before the real auth (Keycloak/Zitadel) module lands.
function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

function withParsedCustomFields(row) {
  if (!row) return row;
  return { ...row, custom_fields: row.custom_fields ? JSON.parse(row.custom_fields) : {} };
}

// GET /leads/referrals — who is actually bringing in business.
router.get('/referrals', async (req, res) => {
  const tid = tenantId(req);

  const topReferrersRow = await db.prepare(`
    SELECT r.id AS referrer_lead_id, r.full_name AS referrer_name,
           COUNT(l.id) AS referred_count,
           SUM(CASE WHEN l.stage = 'Admission' THEN 1 ELSE 0 END) AS converted_count
    FROM leads l JOIN leads r ON r.id = l.referred_by_lead_id
    WHERE l.tenant_id = ? AND l.deleted_at IS NULL
    GROUP BY r.id ORDER BY referred_count DESC LIMIT 20
  `).all(tid);

  const externalReferrers = await db.prepare(`
    SELECT referrer_name, referrer_type, COUNT(*) AS referred_count,
           SUM(CASE WHEN stage = 'Admission' THEN 1 ELSE 0 END) AS converted_count
    FROM leads
    WHERE tenant_id = ? AND deleted_at IS NULL AND referrer_name IS NOT NULL AND referred_by_lead_id IS NULL
    GROUP BY referrer_name, referrer_type ORDER BY referred_count DESC LIMIT 20
  `).all(tid);

  const totalReferred = await db.prepare(
    "SELECT COUNT(*) AS c FROM leads WHERE tenant_id = ? AND deleted_at IS NULL AND (referred_by_lead_id IS NOT NULL OR referrer_name IS NOT NULL)"
  ).get(tid);
  const topReferrers = topReferrersRow.c;

  res.json({ total_referred_leads: totalReferred, top_referrers_from_leads: topReferrers, external_referrers: externalReferrers });
});

// GET /leads/check-duplicate?full_name=...&phone=...
router.get('/check-duplicate', async (req, res) => {
  const tid = tenantId(req);
  const { full_name, phone } = req.query;
  if (!full_name && !phone) return res.json([]);
  res.json(await findDuplicates(db, tid, { full_name, phone }));
});

// GET /leads/trash — soft-deleted leads, for the Trash/Recently Deleted
// screen. Kept as a fully separate list from the main GET / so a deleted
// lead never silently shows up in normal browsing/search/pipeline views.
router.get('/trash', async (req, res) => {
  const tid = tenantId(req);
  const rows = await db.prepare(
    'SELECT * FROM leads WHERE tenant_id = ? AND deleted_at IS NOT NULL ORDER BY deleted_at DESC'
  ).all(tid);
  res.json(rows.map(withParsedCustomFields));
});

// GET /leads?stage=New&has_parent=true — list leads, optional filters.
// Soft-deleted leads are excluded by default everywhere leads are browsed;
// this is the single choke point that guarantees that.
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { stage, has_parent, lifecycle_status } = req.query;
  let rows;
  if (has_parent === 'true') {
    rows = await db.prepare("SELECT * FROM leads WHERE tenant_id = ? AND deleted_at IS NULL AND parent_name IS NOT NULL ORDER BY created_at DESC").all(tid);
  } else if (lifecycle_status) {
    rows = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND deleted_at IS NULL AND lifecycle_status = ? ORDER BY created_at DESC')
      .all(tid, lifecycle_status);
  } else if (stage) {
    rows = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND deleted_at IS NULL AND stage = ? ORDER BY created_at DESC')
      .all(tid, stage);
  } else {
    rows = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND deleted_at IS NULL ORDER BY created_at DESC').all(tid);
  }
  res.json(rows.map(withParsedCustomFields));
});

// GET /leads/:id
router.get('/:id', async (req, res) => {
  const tid = tenantId(req);
  const row = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!row) return res.status(404).json({ error: 'Lead not found' });
  res.json(withParsedCustomFields(row));
});

// POST /leads — create a new lead
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { full_name, phone, phone_country_code, email, source, assigned_to, notes, parent_name, parent_phone, parent_relation,
          referred_by_lead_id, referrer_name, referrer_type } = req.body;
  if (!full_name) return res.status(400).json({ error: 'full_name is required' });

  // Country code defaults to the tenant's configured default (set in
  // Settings) if the caller doesn't specify one — this is what makes
  // "auto-pick by country" work without the counselor doing anything,
  // while still being fully overridable per-lead.
  let countryCode = phone_country_code;
  if (!countryCode) {
    const tenant = await db.prepare('SELECT default_country_code FROM tenants WHERE id = ?').get(tid);
    countryCode = tenant?.default_country_code || '+91';
  }

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO leads (id, tenant_id, full_name, phone, phone_country_code, email, source, assigned_to, notes, parent_name, parent_phone, parent_relation,
                       referred_by_lead_id, referrer_name, referrer_type, lifecycle_status)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, full_name, phone || null, countryCode, email || null, source || null, assigned_to || null, notes || null,
         parent_name || null, parent_phone || null, parent_relation || null,
         referred_by_lead_id || null, referrer_name || null, referrer_type || null, 'NEW');

  const created = await db.prepare('SELECT * FROM leads WHERE id = ?').get(id);
  await fireEvent('lead.created', { tenant_id: tid, lead_id: id });
  res.status(201).json(created);
});

// POST /leads/bulk-delete  { lead_ids: [...] }
// Multi-select delete from the Leads List screen. Soft-delete, same as
// the single-lead DELETE below — every bulk action in this app should be
// exactly as safe as its single-item equivalent, never more destructive.
router.post('/bulk-delete', async (req, res) => {
  const tid = tenantId(req);
  const { lead_ids, deleted_by } = req.body;
  if (!Array.isArray(lead_ids) || lead_ids.length === 0) {
    return res.status(400).json({ error: 'lead_ids must be a non-empty array' });
  }
  let count = 0;
  for (const id of lead_ids) {
    const result = await db.prepare(
      "UPDATE leads SET deleted_at = datetime('now'), deleted_by = ? WHERE tenant_id = ? AND id = ? AND deleted_at IS NULL"
    ).run(deleted_by || null, tid, id);
    count += result.changes;
  }
  res.json({ deleted_count: count });
});

// POST /leads/bulk-restore  { lead_ids: [...] }
router.post('/bulk-restore', async (req, res) => {
  const tid = tenantId(req);
  const { lead_ids } = req.body;
  if (!Array.isArray(lead_ids) || lead_ids.length === 0) {
    return res.status(400).json({ error: 'lead_ids must be a non-empty array' });
  }
  let count = 0;
  for (const id of lead_ids) {
    const result = await db.prepare(
      'UPDATE leads SET deleted_at = NULL, deleted_by = NULL WHERE tenant_id = ? AND id = ? AND deleted_at IS NOT NULL'
    ).run(tid, id);
    count += result.changes;
  }
  res.json({ restored_count: count });
});

// PATCH /leads/:id — update fields (e.g. move stage, reassign, add notes)
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Lead not found' });

  const allowed = ['full_name', 'phone', 'phone_country_code', 'email', 'source', 'stage', 'assigned_to', 'notes', 'parent_name', 'parent_phone', 'parent_relation',
                   'referred_by_lead_id', 'referrer_name', 'referrer_type'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) {
      updates.push(`${field} = ?`);
      values.push(req.body[field]);
    }
  }
  if (updates.length === 0 && req.body.custom_fields === undefined) {
    return res.status(400).json({ error: 'No valid fields to update' });
  }

  // Adding a phone to a lead that never had a country code (e.g. imported
  // rows, or one created before this field existed) would otherwise leave
  // phone_country_code null and produce an unroutable wa.me link — the
  // exact class of bug fixed app-wide via services/phone.js. Apply the
  // same tenant-default fallback POST already uses.
  if (req.body.phone !== undefined && req.body.phone_country_code === undefined && !existing.phone_country_code) {
    const tenant = await db.prepare('SELECT default_country_code FROM tenants WHERE id = ?').get(tid);
    updates.push('phone_country_code = ?');
    values.push(tenant?.default_country_code || '+91');
  }

  if (req.body.custom_fields !== undefined) {
    const currentFields = existing.custom_fields ? JSON.parse(existing.custom_fields) : {};
    const merged = { ...currentFields, ...req.body.custom_fields };
    updates.push('custom_fields = ?');
    values.push(JSON.stringify(merged));
  }

  updates.push("updated_at = datetime('now')");
  values.push(tid, req.params.id);

  await db.prepare(`UPDATE leads SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  const updated = await db.prepare('SELECT * FROM leads WHERE id = ?').get(req.params.id);
  if (req.body.stage !== undefined) {
    await fireEvent('lead.stage_changed', { tenant_id: tid, lead_id: req.params.id, stage: req.body.stage });
  }
  res.json(withParsedCustomFields(updated));
});

// DELETE /leads/:id — soft-delete (moves to Trash, recoverable).
// Previously this was a hard DELETE, which would have started failing
// with FK-constraint errors the moment any child record (documents,
// fee_payments, meetings, ...) existed for the lead — same class of bug
// already fixed once for review_providers. Soft-delete sidesteps that
// entirely and is also just safer: a lead has 14+ dependent tables, and
// an accidental permanent delete would be a serious data-loss incident.
router.delete('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ? AND deleted_at IS NULL').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Lead not found' });

  await db.prepare(
    "UPDATE leads SET deleted_at = datetime('now'), deleted_by = ? WHERE tenant_id = ? AND id = ?"
  ).run(req.body?.deleted_by || null, tid, req.params.id);

  res.status(200).json({ deleted: true, trashed: true });
});

// POST /leads/:id/restore — undo a soft-delete.
router.post('/:id/restore', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare(
    'UPDATE leads SET deleted_at = NULL, deleted_by = NULL WHERE tenant_id = ? AND id = ? AND deleted_at IS NOT NULL'
  ).run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Lead not found in trash' });
  res.json(await db.prepare('SELECT * FROM leads WHERE id = ?').get(req.params.id));
});

module.exports = router;
