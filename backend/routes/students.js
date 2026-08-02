const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { createNotification } = require('./notifications');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

const STUDENT_STATUSES = ['enrolled', 'on-leave', 'graduated', 'discontinued', 'transferred'];

// GET /students?status=enrolled
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { status } = req.query;
  let query = `SELECT s.*, l.full_name, l.phone, l.email, l.parent_name, l.parent_phone
               FROM students s JOIN leads l ON l.id = s.lead_id
               WHERE s.tenant_id = ?`;
  const params = [tid];
  if (status) {
    query += ' AND s.status = ?';
    params.push(status);
  }
  query += ' ORDER BY s.enrolled_date DESC';
  res.json(await db.prepare(query).all(...params));
});

// POST /students — promote an admitted lead into an enrolled student.
// The lead record stays as the person's history (every call, document and
// payment from the enquiry days remains attached); the student record adds
// the ongoing academic relationship on top of it.
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, student_code, institution_name, course_name, batch_year,
          enrolled_date, expected_completion, local_contact, notes } = req.body;

  if (!lead_id || !institution_name) {
    return res.status(400).json({ error: 'lead_id and institution_name are required' });
  }
  const leadRow = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found for this tenant' });

  const existing = await db.prepare('SELECT id FROM students WHERE tenant_id = ? AND lead_id = ?').get(tid, lead_id);
  if (existing) return res.status(409).json({ error: 'This lead is already enrolled as a student' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO students (id, tenant_id, lead_id, student_code, institution_name, course_name,
                          batch_year, enrolled_date, expected_completion, local_contact, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, student_code || null, institution_name, course_name || null,
    batch_year || null, enrolled_date || new Date().toISOString().slice(0, 10),
    expected_completion || null, local_contact || null, notes || null);

  await db.prepare("UPDATE leads SET stage = 'Closed', updated_at = datetime('now') WHERE tenant_id = ? AND id = ?").run(tid, lead_id);

  res.status(201).json(await db.prepare('SELECT * FROM students WHERE id = ?').get(id));
});

// PATCH /students/:id — semester progression, status changes
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT * FROM students WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Student not found' });

  if (req.body.status && !STUDENT_STATUSES.includes(req.body.status)) {
    return res.status(400).json({ error: `status must be one of: ${STUDENT_STATUSES.join(', ')}` });
  }

  const allowed = ['student_code', 'institution_name', 'course_name', 'batch_year',
                   'current_semester', 'status', 'enrolled_date', 'expected_completion', 'local_contact', 'notes'];
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
  await db.prepare(`UPDATE students SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);

  // A student dropping out is both a duty-of-care issue and a reputation
  // risk — it should never be a silent database change.
  if (req.body.status === 'discontinued') {
    const lead = await db.prepare('SELECT full_name FROM leads WHERE id = ?').get(existing.lead_id);
    await createNotification(tid, {
      title: `Student discontinued: ${lead?.full_name || 'student'}`,
      body: `${existing.institution_name} — reach out to the family today.`,
      linkType: 'lead',
      linkId: existing.lead_id,
    });
  }
  if (req.body.status === 'graduated') {
    const lead = await db.prepare('SELECT full_name FROM leads WHERE id = ?').get(existing.lead_id);
    await createNotification(tid, {
      title: `🎓 Graduated: ${lead?.full_name || 'student'}`,
      body: 'Ask for a testimonial and referrals — this is the best moment for both.',
      linkType: 'lead',
      linkId: existing.lead_id,
    });
  }

  res.json(await db.prepare('SELECT * FROM students WHERE id = ?').get(req.params.id));
});

// ---------- Check-ins ----------

router.get('/:id/checkins', async (req, res) => {
  const tid = tenantId(req);
  res.json(await db.prepare(
    'SELECT * FROM student_checkins WHERE tenant_id = ? AND student_id = ? ORDER BY checkin_date DESC'
  ).all(tid, req.params.id));
});

router.post('/:id/checkins', async (req, res) => {
  const tid = tenantId(req);
  const student = await db.prepare('SELECT * FROM students WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!student) return res.status(404).json({ error: 'Student not found' });

  const { wellbeing, academic_status, issues_raised, action_taken, conducted_by } = req.body;
  const id = randomUUID();
  await db.prepare(`
    INSERT INTO student_checkins (id, tenant_id, student_id, wellbeing, academic_status, issues_raised, action_taken, conducted_by)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, req.params.id, wellbeing || null, academic_status || null,
    issues_raised || null, action_taken || null, conducted_by || null);

  // "Struggling" is the earliest signal that a student may drop out —
  // and the point where intervention still works.
  if (wellbeing === 'struggling') {
    const lead = await db.prepare('SELECT full_name FROM leads WHERE id = ?').get(student.lead_id);
    await createNotification(tid, {
      title: `${lead?.full_name || 'A student'} is struggling`,
      body: issues_raised || 'Flagged during a check-in. Needs support.',
      linkType: 'lead',
      linkId: student.lead_id,
    });
  }

  res.status(201).json(await db.prepare('SELECT * FROM student_checkins WHERE id = ?').get(id));
});

// GET /students/stats — the "are our students actually okay" view
router.get('/stats/summary', async (req, res) => {
  const tid = tenantId(req);
  const byStatus = await db.prepare('SELECT status, COUNT(*) AS count FROM students WHERE tenant_id = ? GROUP BY status').all(tid);
  const byInstitution = await db.prepare(
    'SELECT institution_name, COUNT(*) AS count FROM students WHERE tenant_id = ? GROUP BY institution_name ORDER BY count DESC'
  ).all(tid);
  const strugglingCountRow = await db.prepare(`
    SELECT COUNT(DISTINCT student_id) AS c FROM student_checkins
    WHERE tenant_id = ? AND wellbeing = 'struggling'
  `).get(tid);
  const strugglingCount = strugglingCountRow.c;
  const noRecentCheckinRow = await db.prepare(`
    SELECT COUNT(*) AS c FROM students s
    WHERE s.tenant_id = ? AND s.status = 'enrolled'
      AND NOT EXISTS (
        SELECT 1 FROM student_checkins c
        WHERE c.student_id = s.id AND c.checkin_date >= (CURRENT_DATE - INTERVAL '90 days')::text
      )
  `).get(tid);
  const noRecentCheckin = noRecentCheckinRow.c;

  res.json({
    by_status: byStatus,
    by_institution: byInstitution,
    students_flagged_struggling: strugglingCount,
    enrolled_without_checkin_90days: noRecentCheckin,
  });
});

module.exports = router;
