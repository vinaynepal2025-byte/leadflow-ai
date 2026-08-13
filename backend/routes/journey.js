const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { createNotification } = require('./notifications');
const { createReminder } = require('./reminders');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

const VISA_STATUSES = [
  'Not Started', 'Documents Pending', 'Submitted', 'Biometrics Done',
  'Interview Scheduled', 'Approved', 'Rejected', 'Appealing',
];

// ---------- Visa ----------

// GET /journey/visa?lead_id=xxx
router.get('/visa', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  const rows = lead_id
    ? await db.prepare('SELECT * FROM visa_applications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC').all(tid, lead_id)
    : await db.prepare(`SELECT v.*, l.full_name AS lead_name FROM visa_applications v
                  JOIN leads l ON l.id = v.lead_id
                  WHERE v.tenant_id = ? ORDER BY v.updated_at DESC`).all(tid);
  res.json(rows);
});

router.post('/visa', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, country, visa_type, embassy_location, notes } = req.body;
  if (!lead_id || !country) return res.status(400).json({ error: 'lead_id and country are required' });

  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found for this tenant' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO visa_applications (id, tenant_id, lead_id, country, visa_type, embassy_location, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, country, visa_type || 'Student', embassy_location || null, notes || null);

  res.status(201).json(await db.prepare('SELECT * FROM visa_applications WHERE id = ?').get(id));
});

router.patch('/visa/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT * FROM visa_applications WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Visa application not found' });

  if (req.body.status && !VISA_STATUSES.includes(req.body.status)) {
    return res.status(400).json({ error: `status must be one of: ${VISA_STATUSES.join(', ')}` });
  }

  const allowed = ['country', 'visa_type', 'status', 'application_number', 'submitted_date',
                   'interview_date', 'decision_date', 'embassy_location', 'rejection_reason', 'notes'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) {
      updates.push(`${field} = ?`);
      values.push(req.body[field]);
    }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });

  updates.push("updated_at = datetime('now')");
  values.push(tid, req.params.id);
  await db.prepare(`UPDATE visa_applications SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);

  // Visa outcomes are the highest-stakes events in the whole journey —
  // both directions need to reach a human immediately.
  if (req.body.status === 'Rejected' || req.body.status === 'Approved') {
    const lead = await db.prepare('SELECT full_name FROM leads WHERE id = ?').get(existing.lead_id);
    await createNotification(tid, {
      title: `Visa ${req.body.status}: ${lead?.full_name || 'lead'}`,
      body: req.body.status === 'Rejected'
        ? `${existing.country} visa rejected. ${req.body.rejection_reason || 'Reason not recorded yet.'}`
        : `${existing.country} visa approved — start travel planning.`,
      linkType: 'lead',
      linkId: existing.lead_id,
    });
  }
  if (req.body.interview_date) {
    await createReminder(tid, {
      leadId: existing.lead_id,
      title: `Visa interview — ${existing.country}`,
      dueAt: new Date(new Date(req.body.interview_date).getTime() - 24 * 60 * 60 * 1000).toISOString(),
    });
  }

  res.json(await db.prepare('SELECT * FROM visa_applications WHERE id = ?').get(req.params.id));
});

// ---------- Visa document checklist ----------
//
// Tenant-configurable master templates (country + visa_type -> required
// doc_types), cross-referenced against the lead's actual Documents rows.
// This is the concrete "no loopholes" fix for visa applications: instead
// of a counselor remembering what's needed for each country, the system
// tracks it and tells them exactly what's missing.

// GET /journey/checklist-templates?country=USA&visa_type=Student
router.get('/checklist-templates', async (req, res) => {
  const tid = tenantId(req);
  const { country, visa_type } = req.query;
  let query = 'SELECT * FROM visa_checklist_items WHERE tenant_id = ?';
  const params = [tid];
  if (country) {
    query += ' AND country = ?';
    params.push(country);
  }
  if (visa_type) {
    query += ' AND visa_type = ?';
    params.push(visa_type);
  }
  query += ' ORDER BY country, visa_type, display_order';
  res.json(await db.prepare(query).all(...params));
});

// POST /journey/checklist-templates — tenant adds/customizes a required doc
router.post('/checklist-templates', async (req, res) => {
  const tid = tenantId(req);
  const { country, visa_type, doc_type, display_order } = req.body;
  if (!country || !doc_type) return res.status(400).json({ error: 'country and doc_type are required' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO visa_checklist_items (id, tenant_id, country, visa_type, doc_type, display_order)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(id, tid, country, visa_type || 'Student', doc_type, display_order || 0);

  res.status(201).json(await db.prepare('SELECT * FROM visa_checklist_items WHERE id = ?').get(id));
});

// DELETE /journey/checklist-templates/:id
router.delete('/checklist-templates/:id', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare('DELETE FROM visa_checklist_items WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Checklist item not found' });
  res.status(204).send();
});

// GET /journey/visa/:id/checklist — the actual per-lead, per-visa view:
// every required doc for this visa's country/type, marked against what
// the lead has actually uploaded (matched by doc_type, case-insensitive).
router.get('/visa/:id/checklist', async (req, res) => {
  const tid = tenantId(req);
  const visa = await db.prepare('SELECT * FROM visa_applications WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!visa) return res.status(404).json({ error: 'Visa application not found' });

  const required = await db.prepare(
    'SELECT * FROM visa_checklist_items WHERE tenant_id = ? AND country = ? AND visa_type = ? ORDER BY display_order'
  ).all(tid, visa.country, visa.visa_type);

  const leadDocs = await db.prepare('SELECT doc_type, status FROM documents WHERE tenant_id = ? AND lead_id = ?')
    .all(tid, visa.lead_id);
  const docsByType = new Map();
  for (const d of leadDocs) docsByType.set(d.doc_type.trim().toLowerCase(), d.status);

  const checklist = required.map((item) => {
    const match = docsByType.get(item.doc_type.trim().toLowerCase());
    return {
      doc_type: item.doc_type,
      status: match || 'missing', // 'missing' | 'pending' | 'verified' | 'rejected'
    };
  });

  const missingCount = checklist.filter((c) => c.status === 'missing' || c.status === 'rejected').length;
  res.json({ visa_id: visa.id, country: visa.country, visa_type: visa.visa_type, checklist, missing_count: missingCount });
});

// ---------- Travel ----------

router.get('/travel', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  const rows = lead_id
    ? await db.prepare('SELECT * FROM travel_plans WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC').all(tid, lead_id)
    : await db.prepare(`SELECT t.*, l.full_name AS lead_name FROM travel_plans t
                  JOIN leads l ON l.id = t.lead_id
                  WHERE t.tenant_id = ? ORDER BY t.departure_date ASC`).all(tid);
  res.json(rows);
});

router.post('/travel', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, departure_date, departure_city, arrival_date, arrival_city,
          airline, flight_number, accommodation, pickup_arranged, pickup_contact, notes } = req.body;
  if (!lead_id) return res.status(400).json({ error: 'lead_id is required' });

  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found for this tenant' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO travel_plans (id, tenant_id, lead_id, departure_date, departure_city, arrival_date,
                              arrival_city, airline, flight_number, accommodation, pickup_arranged, pickup_contact, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, departure_date || null, departure_city || null, arrival_date || null,
    arrival_city || null, airline || null, flight_number || null, accommodation || null,
    pickup_arranged ? 1 : 0, pickup_contact || null, notes || null);

  if (departure_date) {
    await createReminder(tid, {
      leadId: lead_id,
      title: `Confirm airport pickup — departs ${departure_date}`,
      dueAt: new Date(new Date(departure_date).getTime() - 3 * 24 * 60 * 60 * 1000).toISOString(),
    });
  }

  res.status(201).json(await db.prepare('SELECT * FROM travel_plans WHERE id = ?').get(id));
});

router.patch('/travel/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM travel_plans WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Travel plan not found' });

  const allowed = ['departure_date', 'departure_city', 'arrival_date', 'arrival_city', 'airline',
                   'flight_number', 'accommodation', 'pickup_arranged', 'pickup_contact', 'status', 'notes'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) {
      updates.push(`${field} = ?`);
      values.push(field === 'pickup_arranged' ? (req.body[field] ? 1 : 0) : req.body[field]);
    }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });

  values.push(tid, req.params.id);
  await db.prepare(`UPDATE travel_plans SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  res.json(await db.prepare('SELECT * FROM travel_plans WHERE id = ?').get(req.params.id));
});

module.exports = router;
