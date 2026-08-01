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
// Word-of-mouth is the top channel for consultancies but is usually
// invisible in a CRM; this makes it countable.
router.get('/referrals', async (req, res) => {
  const tid = tenantId(req);

  const topReferrers = await db.prepare(`
    SELECT r.id AS referrer_lead_id, r.full_name AS referrer_name,
           COUNT(l.id) AS referred_count,
           SUM(CASE WHEN l.stage = 'Admission' THEN 1 ELSE 0 END) AS converted_count
    FROM leads l JOIN leads r ON r.id = l.referred_by_lead_id
    WHERE l.tenant_id = ?
    GROUP BY r.id ORDER BY referred_count DESC LIMIT 20
  `).all(tid);

  const externalReferrers = await db.prepare(`
    SELECT referrer_name, referrer_type, COUNT(*) AS referred_count,
           SUM(CASE WHEN stage = 'Admission' THEN 1 ELSE 0 END) AS converted_count
    FROM leads
    WHERE tenant_id = ? AND referrer_name IS NOT NULL AND referred_by_lead_id IS NULL
    GROUP BY referrer_name, referrer_type ORDER BY referred_count DESC LIMIT 20
  `).all(tid);

  const totalReferred = await db.prepare(
    'SELECT COUNT(*) AS c FROM leads WHERE tenant_id = ? AND (referred_by_lead_id IS NOT NULL OR referrer_name IS NOT NULL)'
  ).get(tid).c;

  res.json({ total_referred_leads: totalReferred, top_referrers_from_leads: topReferrers, external_referrers: externalReferrers });
});

// GET /leads/check-duplicate?full_name=...&phone=...
// Used before creating a lead — the app calls this first, shows candidates,
// and the counselor decides whether to proceed or link to an existing lead.
router.get('/check-duplicate', async (req, res) => {
  const tid = tenantId(req);
  const { full_name, phone } = req.query;
  if (!full_name && !phone) return res.json([]);
  res.json(await findDuplicates(db, tid, { full_name, phone }));
});

// GET /leads?stage=New&has_parent=true — list leads, optional filters
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { stage, has_parent } = req.query;
  let rows;
  if (has_parent === 'true') {
    rows = await db.prepare("SELECT * FROM leads WHERE tenant_id = ? AND parent_name IS NOT NULL ORDER BY created_at DESC").all(tid);
  } else if (stage) {
    rows = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND stage = ? ORDER BY created_at DESC')
      .all(tid, stage);
  } else {
    rows = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? ORDER BY created_at DESC').all(tid);
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
  const { full_name, phone, email, source, assigned_to, notes, parent_name, parent_phone, parent_relation,
          referred_by_lead_id, referrer_name, referrer_type } = req.body;
  if (!full_name) return res.status(400).json({ error: 'full_name is required' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO leads (id, tenant_id, full_name, phone, email, source, assigned_to, notes, parent_name, parent_phone, parent_relation,
                       referred_by_lead_id, referrer_name, referrer_type)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, full_name, phone || null, email || null, source || null, assigned_to || null, notes || null,
         parent_name || null, parent_phone || null, parent_relation || null,
         referred_by_lead_id || null, referrer_name || null, referrer_type || null);

  const created = await db.prepare('SELECT * FROM leads WHERE id = ?').get(id);
  await fireEvent('lead.created', { tenant_id: tid, lead_id: id });
  res.status(201).json(created);
});

// PATCH /leads/:id — update fields (e.g. move stage, reassign, add notes)
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Lead not found' });

  const allowed = ['full_name', 'phone', 'email', 'source', 'stage', 'assigned_to', 'notes', 'parent_name', 'parent_phone', 'parent_relation',
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

  // custom_fields is a merge (add/update individual keys), not a full
  // overwrite — so setting one custom field never wipes out the others.
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

// DELETE /leads/:id
router.delete('/:id', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare('DELETE FROM leads WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Lead not found' });
  res.status(204).send();
});

module.exports = router;
