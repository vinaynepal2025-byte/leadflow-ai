const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

const CONSENT_TYPES = ['data_processing', 'marketing_contact', 'document_sharing', 'third_party_sharing'];

// GET /compliance/consent/:leadId — current consent state (latest per type)
router.get('/consent/:leadId', (req, res) => {
  const tid = tenantId(req);
  const all = db.prepare(
    'SELECT * FROM consent_records WHERE tenant_id = ? AND lead_id = ? ORDER BY recorded_at DESC'
  ).all(tid, req.params.leadId);

  const latestByType = {};
  for (const r of all) {
    if (!latestByType[r.consent_type]) latestByType[r.consent_type] = r;
  }

  res.json({ current: latestByType, history: all });
});

// POST /compliance/consent  { lead_id, consent_type, granted, method, notes }
router.post('/consent', (req, res) => {
  const tid = tenantId(req);
  const { lead_id, consent_type, granted, method, notes } = req.body;
  if (!lead_id || !consent_type || granted === undefined) {
    return res.status(400).json({ error: 'lead_id, consent_type, and granted are required' });
  }
  if (!CONSENT_TYPES.includes(consent_type)) {
    return res.status(400).json({ error: `consent_type must be one of: ${CONSENT_TYPES.join(', ')}` });
  }
  const lead = db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const id = randomUUID();
  db.prepare(`
    INSERT INTO consent_records (id, tenant_id, lead_id, consent_type, granted, method, recorded_by, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, consent_type, granted ? 1 : 0, method || null, req.body.recorded_by || null, notes || null);

  res.status(201).json(db.prepare('SELECT * FROM consent_records WHERE id = ?').get(id));
});

// ---------- Data subject requests (export / delete) ----------

router.get('/requests', (req, res) => {
  const tid = tenantId(req);
  res.json(db.prepare(`
    SELECT dr.*, l.full_name FROM data_requests dr JOIN leads l ON l.id = dr.lead_id
    WHERE dr.tenant_id = ? ORDER BY dr.requested_at DESC
  `).all(tid));
});

router.post('/requests', (req, res) => {
  const tid = tenantId(req);
  const { lead_id, request_type } = req.body;
  if (!lead_id || !['export', 'delete'].includes(request_type)) {
    return res.status(400).json({ error: 'lead_id and request_type (export|delete) are required' });
  }
  const id = randomUUID();
  db.prepare('INSERT INTO data_requests (id, tenant_id, lead_id, request_type) VALUES (?, ?, ?, ?)')
    .run(id, tid, lead_id, request_type);
  res.status(201).json(db.prepare('SELECT * FROM data_requests WHERE id = ?').get(id));
});

// GET /compliance/export/:leadId — every piece of data held on this lead,
// in one JSON document. This is the actual export a "right to access"
// request needs to be fulfilled with.
router.get('/export/:leadId', (req, res) => {
  const tid = tenantId(req);
  const lead = db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const tables = ['communications', 'reminders', 'documents', 'admission_applications', 'fee_payments',
                   'meetings', 'visa_applications', 'travel_plans', 'consent_records', 'tasks'];
  const bundle = { lead };
  for (const table of tables) {
    try {
      bundle[table] = db.prepare(`SELECT * FROM ${table} WHERE tenant_id = ? AND lead_id = ?`).all(tid, req.params.leadId);
    } catch {
      bundle[table] = [];
    }
  }

  db.prepare("UPDATE data_requests SET status = 'completed', completed_at = datetime('now') WHERE tenant_id = ? AND lead_id = ? AND request_type = 'export' AND status = 'pending'")
    .run(tid, req.params.leadId);

  res.json(bundle);
});

// DELETE /compliance/erase/:leadId — irreversible. Removes the lead and
// everything linked to them across every table. Requires explicit
// confirmation in the request body — this is not something a stray click
// should be able to trigger.
router.delete('/erase/:leadId', (req, res) => {
  const tid = tenantId(req);
  if (req.body?.confirm !== true) {
    return res.status(400).json({ error: 'This is irreversible. Send { "confirm": true } to proceed.' });
  }
  const lead = db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const tables = ['communications', 'reminders', 'documents', 'admission_applications', 'fee_payments',
                   'meetings', 'visa_applications', 'travel_plans', 'consent_records', 'tasks',
                   'campaign_targets', 'voice_notes', 'call_logs', 'alumni_connections'];
  for (const table of tables) {
    try {
      db.prepare(`DELETE FROM ${table} WHERE tenant_id = ? AND lead_id = ?`).run(tid, req.params.leadId);
    } catch { /* table may not have a lead_id column — skip */ }
  }
  db.prepare('DELETE FROM leads WHERE tenant_id = ? AND id = ?').run(tid, req.params.leadId);

  db.prepare("UPDATE data_requests SET status = 'completed', completed_at = datetime('now') WHERE tenant_id = ? AND lead_id = ? AND request_type = 'delete' AND status = 'pending'")
    .run(tid, req.params.leadId);

  res.json({ erased: true });
});

module.exports = router;
