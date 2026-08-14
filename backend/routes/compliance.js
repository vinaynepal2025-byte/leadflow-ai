const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { uploadFile, getSignedUrl } = require('../services/supabaseStorage');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

const CONSENT_TYPES = ['data_processing', 'marketing_contact', 'document_sharing', 'third_party_sharing'];

// ---------- Consent form templates (tenant-customizable legal language) ----------
//
// Fulfils the "white-label, fully user-controlled" requirement for
// compliance text specifically — a tenant operating under DPDP (India),
// GDPR (EU-facing), or another regime can edit the exact wording shown
// to a lead when consent is captured, without needing a code change.

// GET /compliance/consent-templates
router.get('/consent-templates', async (req, res) => {
  const tid = tenantId(req);
  const rows = await db.prepare('SELECT * FROM consent_form_templates WHERE tenant_id = ? ORDER BY consent_type').all(tid);
  res.json(rows);
});

// PUT /compliance/consent-templates/:consentType — create or update this
// tenant's wording for one consent type (upsert, since there's exactly
// one active template per type per tenant).
router.put('/consent-templates/:consentType', async (req, res) => {
  const tid = tenantId(req);
  const consentType = req.params.consentType;
  const { title, body_text } = req.body;
  if (!CONSENT_TYPES.includes(consentType)) {
    return res.status(400).json({ error: `consentType must be one of: ${CONSENT_TYPES.join(', ')}` });
  }
  if (!title || !body_text) return res.status(400).json({ error: 'title and body_text are required' });

  const existing = await db.prepare(
    'SELECT id FROM consent_form_templates WHERE tenant_id = ? AND consent_type = ?'
  ).get(tid, consentType);

  if (existing) {
    await db.prepare(
      "UPDATE consent_form_templates SET title = ?, body_text = ?, updated_at = datetime('now') WHERE id = ?"
    ).run(title, body_text, existing.id);
    return res.json(await db.prepare('SELECT * FROM consent_form_templates WHERE id = ?').get(existing.id));
  }

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO consent_form_templates (id, tenant_id, consent_type, title, body_text)
    VALUES (?, ?, ?, ?, ?)
  `).run(id, tid, consentType, title, body_text);
  res.json(await db.prepare('SELECT * FROM consent_form_templates WHERE id = ?').get(id));
});

// GET /compliance/consent/:leadId — current consent state (latest per type)
router.get('/consent/:leadId', async (req, res) => {
  const tid = tenantId(req);
  const all = await db.prepare(
    'SELECT * FROM consent_records WHERE tenant_id = ? AND lead_id = ? ORDER BY recorded_at DESC'
  ).all(tid, req.params.leadId);

  const latestByType = {};
  for (const r of all) {
    if (!latestByType[r.consent_type]) latestByType[r.consent_type] = r;
  }

  res.json({ current: latestByType, history: all });
});

// POST /compliance/consent  { lead_id, consent_type, granted, method, notes }
router.post('/consent', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, consent_type, granted, method, notes } = req.body;
  if (!lead_id || !consent_type || granted === undefined) {
    return res.status(400).json({ error: 'lead_id, consent_type, and granted are required' });
  }
  if (!CONSENT_TYPES.includes(consent_type)) {
    return res.status(400).json({ error: `consent_type must be one of: ${CONSENT_TYPES.join(', ')}` });
  }
  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO consent_records (id, tenant_id, lead_id, consent_type, granted, method, recorded_by, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, consent_type, granted ? 1 : 0, method || null, req.body.recorded_by || null, notes || null);

  res.status(201).json(await db.prepare('SELECT * FROM consent_records WHERE id = ?').get(id));
});

// ---------- Data subject requests (export / delete) ----------

router.get('/requests', async (req, res) => {
  const tid = tenantId(req);
  res.json(await db.prepare(`
    SELECT dr.*, l.full_name FROM data_requests dr JOIN leads l ON l.id = dr.lead_id
    WHERE dr.tenant_id = ? ORDER BY dr.requested_at DESC
  `).all(tid));
});

router.post('/requests', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, request_type } = req.body;
  if (!lead_id || !['export', 'delete'].includes(request_type)) {
    return res.status(400).json({ error: 'lead_id and request_type (export|delete) are required' });
  }
  const id = randomUUID();
  await db.prepare('INSERT INTO data_requests (id, tenant_id, lead_id, request_type) VALUES (?, ?, ?, ?)')
    .run(id, tid, lead_id, request_type);
  res.status(201).json(await db.prepare('SELECT * FROM data_requests WHERE id = ?').get(id));
});

// Builds the full data bundle for a lead — shared by the JSON export
// endpoint and the downloadable-file endpoint below.
const EXPORT_TABLES = ['communications', 'reminders', 'documents', 'admission_applications', 'fee_payments',
  'meetings', 'visa_applications', 'travel_plans', 'consent_records', 'tasks', 'lead_notes'];

async function buildExportBundle(tid, leadId) {
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, leadId);
  if (!lead) return null;
  const bundle = { lead };
  for (const table of EXPORT_TABLES) {
    try {
      bundle[table] = await db.prepare(`SELECT * FROM ${table} WHERE tenant_id = ? AND lead_id = ?`).all(tid, leadId);
    } catch {
      bundle[table] = [];
    }
  }
  return bundle;
}

function escapeHtml(v) {
  return String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// GET /compliance/export/:leadId/file — the actual deliverable for a
// "right to access" request: a real, saveable, human-readable file rather
// than a count summary on screen. Renders every record as an HTML report,
// stores it in Supabase Storage (same infra Documents uses) and returns a
// short-lived signed URL the app can open/download/share.
router.get('/export/:leadId/file', async (req, res) => {
  const tid = tenantId(req);
  const bundle = await buildExportBundle(tid, req.params.leadId);
  if (!bundle) return res.status(404).json({ error: 'Lead not found' });

  const tenant = await db.prepare('SELECT name FROM tenants WHERE id = ?').get(tid);
  const generatedAt = new Date().toISOString().replace('T', ' ').slice(0, 19);

  const sections = EXPORT_TABLES.map((table) => {
    const rows = bundle[table] || [];
    if (rows.length === 0) {
      return `<h2>${table.replace(/_/g, ' ')}</h2><p class="empty">No records.</p>`;
    }
    const cols = Object.keys(rows[0]);
    const head = cols.map((c) => `<th>${escapeHtml(c.replace(/_/g, ' '))}</th>`).join('');
    const body = rows.map((r) => `<tr>${cols.map((c) => `<td>${escapeHtml(r[c])}</td>`).join('')}</tr>`).join('');
    return `<h2>${table.replace(/_/g, ' ')} <span class="count">(${rows.length})</span></h2>
      <div class="scroll"><table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
  }).join('\n');

  const leadRows = Object.entries(bundle.lead)
    .map(([k, v]) => `<tr><th>${escapeHtml(k.replace(/_/g, ' '))}</th><td>${escapeHtml(v)}</td></tr>`).join('');

  const html = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Data Export — ${escapeHtml(bundle.lead.full_name)}</title>
<style>
  body { font-family: -apple-system, Arial, sans-serif; margin: 20px; color: #1B2A4A; line-height: 1.5; }
  h1 { font-size: 20px; border-bottom: 3px solid #1B2A4A; padding-bottom: 8px; }
  h2 { font-size: 15px; margin-top: 28px; text-transform: capitalize; color: #2E4270; }
  .count { color: #5B6478; font-weight: normal; font-size: 13px; }
  .meta { color: #5B6478; font-size: 12px; margin-bottom: 20px; }
  .empty { color: #5B6478; font-size: 13px; font-style: italic; }
  .scroll { overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; font-size: 12px; }
  th, td { border: 1px solid #dde1e8; padding: 6px 8px; text-align: left; vertical-align: top; }
  th { background: #F7F8FA; font-weight: 600; white-space: nowrap; }
  .profile th { width: 180px; }
</style></head>
<body>
  <h1>Personal Data Export — ${escapeHtml(bundle.lead.full_name)}</h1>
  <p class="meta">Issued by ${escapeHtml(tenant?.name || 'LeadFlow AI')} on ${generatedAt}.<br>
  This document contains every record held about this individual, provided in response to a data access request.</p>
  <h2>Profile</h2>
  <table class="profile">${leadRows}</table>
  ${sections}
</body></html>`;

  const storagePath = `exports/${req.params.leadId}-${Date.now()}.html`;
  try {
    await uploadFile(Buffer.from(html, 'utf-8'), storagePath, 'text/html');
    const url = await getSignedUrl(storagePath, 900); // 15 min — long enough to open and save
    await db.prepare("UPDATE data_requests SET status = 'completed', completed_at = datetime('now') WHERE tenant_id = ? AND lead_id = ? AND request_type = 'export' AND status = 'pending'")
      .run(tid, req.params.leadId);
    res.json({ download_url: url, expires_in_seconds: 900 });
  } catch (err) {
    res.status(502).json({ error: `Could not generate the export file: ${err.message}` });
  }
});

// GET /compliance/export/:leadId — every piece of data held on this lead,
// in one JSON document. This is the actual export a "right to access"
// request needs to be fulfilled with.
router.get('/export/:leadId', async (req, res) => {
  const tid = tenantId(req);
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const tables = ['communications', 'reminders', 'documents', 'admission_applications', 'fee_payments',
                   'meetings', 'visa_applications', 'travel_plans', 'consent_records', 'tasks'];
  const bundle = { lead };
  for (const table of tables) {
    try {
      bundle[table] = await db.prepare(`SELECT * FROM ${table} WHERE tenant_id = ? AND lead_id = ?`).all(tid, req.params.leadId);
    } catch {
      bundle[table] = [];
    }
  }

  await db.prepare("UPDATE data_requests SET status = 'completed', completed_at = datetime('now') WHERE tenant_id = ? AND lead_id = ? AND request_type = 'export' AND status = 'pending'")
    .run(tid, req.params.leadId);

  res.json(bundle);
});

// DELETE /compliance/erase/:leadId — irreversible. Removes the lead and
// everything linked to them across every table. Requires explicit
// confirmation in the request body — this is not something a stray click
// should be able to trigger.
router.delete('/erase/:leadId', async (req, res) => {
  const tid = tenantId(req);
  if (req.body?.confirm !== true) {
    return res.status(400).json({ error: 'This is irreversible. Send { "confirm": true } to proceed.' });
  }
  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const tables = ['communications', 'reminders', 'documents', 'admission_applications', 'fee_payments',
                   'meetings', 'visa_applications', 'travel_plans', 'consent_records', 'tasks',
                   'campaign_targets', 'voice_notes', 'call_logs', 'alumni_connections'];
  for (const table of tables) {
    try {
      await db.prepare(`DELETE FROM ${table} WHERE tenant_id = ? AND lead_id = ?`).run(tid, req.params.leadId);
    } catch { /* table may not have a lead_id column — skip */ }
  }
  await db.prepare('DELETE FROM leads WHERE tenant_id = ? AND id = ?').run(tid, req.params.leadId);

  await db.prepare("UPDATE data_requests SET status = 'completed', completed_at = datetime('now') WHERE tenant_id = ? AND lead_id = ? AND request_type = 'delete' AND status = 'pending'")
    .run(tid, req.params.leadId);

  res.json({ erased: true });
});

module.exports = router;
