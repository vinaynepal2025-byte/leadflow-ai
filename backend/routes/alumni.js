const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { createNotification } = require('./notifications');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// PUT /alumni/availability/:studentId — a student opting in/out
router.put('/availability/:studentId', async (req, res) => {
  const tid = tenantId(req);
  const student = await db.prepare('SELECT id FROM students WHERE tenant_id = ? AND id = ?').get(tid, req.params.studentId);
  if (!student) return res.status(404).json({ error: 'Student not found' });

  const { available_for_contact, preferred_channel, bio, max_active_connections } = req.body;
  await db.prepare(`
    INSERT INTO alumni_availability (student_id, available_for_contact, preferred_channel, bio, max_active_connections, updated_at)
    VALUES (?, ?, ?, ?, ?, datetime('now'))
    ON CONFLICT(student_id) DO UPDATE SET
      available_for_contact = excluded.available_for_contact,
      preferred_channel = excluded.preferred_channel,
      bio = excluded.bio,
      max_active_connections = excluded.max_active_connections,
      updated_at = datetime('now')
  `).run(req.params.studentId, available_for_contact ? 1 : 0, preferred_channel || 'whatsapp', bio || null, max_active_connections || 3);

  res.json(await db.prepare('SELECT * FROM alumni_availability WHERE student_id = ?').get(req.params.studentId));
});

// GET /alumni/match/:leadId — find available alumni at the institution(s)
// this lead is applying to, sorted by who has fewest active connections
// (spreads the load rather than always pinging the same one or two people).
router.get('/match/:leadId', async (req, res) => {
  const tid = tenantId(req);
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const targetInstitutions = await db.prepare(
    'SELECT DISTINCT institution_name FROM admission_applications WHERE tenant_id = ? AND lead_id = ?'
  ).all(tid, req.params.leadId).map((r) => r.institution_name);

  if (targetInstitutions.length === 0) {
    return res.json({ matches: [], note: 'This lead has no university applications on file yet — add one to find matching alumni.' });
  }

  const placeholders = targetInstitutions.map(() => '?').join(',');
  const matches = await db.prepare(`
    SELECT s.id AS student_id, l.full_name, s.institution_name, s.course_name, s.current_semester, s.status,
           a.preferred_channel, a.bio,
           (SELECT COUNT(*) FROM alumni_connections c WHERE c.student_id = s.id AND c.status IN ('requested','connected')) AS active_connections
    FROM students s
    JOIN leads l ON l.id = s.lead_id
    JOIN alumni_availability a ON a.student_id = s.id
    WHERE s.tenant_id = ? AND s.institution_name IN (${placeholders})
      AND a.available_for_contact = 1
      AND s.status IN ('enrolled', 'graduated')
    ORDER BY active_connections ASC
  `).all(tid, ...targetInstitutions).filter((m) => m.active_connections < (m.max_active_connections || 3));

  res.json({ matched_institutions: targetInstitutions, matches });
});

// POST /alumni/connect — request a connection between a lead and an alumnus
router.post('/connect', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, student_id } = req.body;
  if (!lead_id || !student_id) return res.status(400).json({ error: 'lead_id and student_id are required' });

  const student = await db.prepare('SELECT * FROM students WHERE tenant_id = ? AND id = ?').get(tid, student_id);
  if (!student) return res.status(404).json({ error: 'Student not found' });

  const id = randomUUID();
  await db.prepare('INSERT INTO alumni_connections (id, tenant_id, lead_id, student_id) VALUES (?, ?, ?, ?)')
    .run(id, tid, lead_id, student_id);

  await createNotification(tid, {
    title: 'Alumni connection requested',
    body: `Ready to introduce — reach out to the alumnus to confirm before sharing contact details.`,
    linkType: 'lead',
    linkId: lead_id,
  });

  res.status(201).json(await db.prepare('SELECT * FROM alumni_connections WHERE id = ?').get(id));
});

router.patch('/connect/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM alumni_connections WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Connection not found' });

  const { status, notes } = req.body;
  await db.prepare('UPDATE alumni_connections SET status = COALESCE(?, status), notes = COALESCE(?, notes) WHERE id = ?')
    .run(status || null, notes || null, req.params.id);
  res.json(await db.prepare('SELECT * FROM alumni_connections WHERE id = ?').get(req.params.id));
});

router.get('/connections', async (req, res) => {
  const tid = tenantId(req);
  res.json(await db.prepare(`
    SELECT ac.*, l.full_name AS lead_name, sl.full_name AS student_name, s.institution_name
    FROM alumni_connections ac
    JOIN leads l ON l.id = ac.lead_id
    JOIN students s ON s.id = ac.student_id
    JOIN leads sl ON sl.id = s.lead_id
    WHERE ac.tenant_id = ? ORDER BY ac.requested_at DESC
  `).all(tid));
});

module.exports = router;
