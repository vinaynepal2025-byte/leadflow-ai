const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { createNotification } = require('./notifications');

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
    await db.prepare(`
      INSERT INTO reminders (id, tenant_id, lead_id, title, due_at, assigned_to)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(randomUUID(), tid, existing.lead_id, `Visa interview — ${existing.country}`,
      new Date(new Date(req.body.interview_date).getTime() - 24 * 60 * 60 * 1000).toISOString(), null);
  }

  res.json(await db.prepare('SELECT * FROM visa_applications WHERE id = ?').get(req.params.id));
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
