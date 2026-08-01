const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

const APPLICATION_STAGES = [
  'Preparing', 'Submitted', 'Under Review', 'Offer', 'Accepted', 'Rejected', 'Withdrawn',
];

// GET /admissions?lead_id=xxx
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  const rows = lead_id
    ? await db.prepare('SELECT * FROM admission_applications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC').all(tid, lead_id)
    : await db.prepare('SELECT * FROM admission_applications WHERE tenant_id = ? ORDER BY created_at DESC').all(tid);
  res.json(rows);
});

// POST /admissions — add a new university application for a lead
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, institution_name, course_name, intake, scholarship_amount, tuition_fee, notes } = req.body;
  if (!lead_id || !institution_name) {
    return res.status(400).json({ error: 'lead_id and institution_name are required' });
  }
  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found for this tenant' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO admission_applications
      (id, tenant_id, lead_id, institution_name, course_name, intake, scholarship_amount, tuition_fee, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, institution_name, course_name || null, intake || null,
         scholarship_amount || null, tuition_fee || null, notes || null);

  res.status(201).json(await db.prepare('SELECT * FROM admission_applications WHERE id = ?').get(id));
});

// PATCH /admissions/:id — update status, scholarship, notes, etc.
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT * FROM admission_applications WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Application not found' });

  if (req.body.application_status && !APPLICATION_STAGES.includes(req.body.application_status)) {
    return res.status(400).json({ error: `application_status must be one of: ${APPLICATION_STAGES.join(', ')}` });
  }

  const allowed = ['institution_name', 'course_name', 'intake', 'application_status', 'scholarship_amount', 'tuition_fee', 'notes'];
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
  await db.prepare(`UPDATE admission_applications SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  res.json(await db.prepare('SELECT * FROM admission_applications WHERE id = ?').get(req.params.id));
});

module.exports = router;
