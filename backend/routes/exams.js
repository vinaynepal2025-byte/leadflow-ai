// Exam Intelligence + Report Card System — HTTP routes.
// See services/examIntelligence.js for the ground rules this route file
// exists to enforce (SQL-computed figures, blocked-not-guessed imports,
// logged-not-overwritten corrections, never-repaired guardian numbers,
// grounded-or-fallback AI narrative).

const express = require('express');
const multer = require('multer');
const db = require('../db');
const {
  parseMarksSheetBuffer,
  importMarks,
  computeReportCard,
  generateNarrative,
  normalizeGuardianPhone,
  getOrCreateDefaultTemplate,
  updateAssessment,
  DEFAULT_TEMPLATE_CONFIG,
} = require('../services/examIntelligence');
const { renderReportCardPng } = require('../services/reportCardImage');
const { uploadFile, getSignedUrl } = require('../services/supabaseStorage');
const { sendWhatsAppImage } = require('../services/whatsapp');
const { buildWhatsAppLink } = require('../services/phone');

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });

function tenantId(req) {
  return req.user?.tenantId || req.header('x-tenant-id') || 'demo-consultancy';
}

/// Two-tier scoping, enforced here because the backend connects to
/// Postgres as a role that bypasses RLS (see this repo's DECISION_LOG.md —
/// the database-level policies are real but dormant until this app issues
/// Supabase-recognized sessions). owner/admin see every student in the
/// tenant; everyone else only a student whose lead is assigned to them.
async function canAccessStudent(req, studentId) {
  const tid = tenantId(req);
  if (!req.user) return false; // no verified identity -> deny, don't guess
  if (['owner', 'admin'].includes(req.user.role)) {
    const row = await db.prepare('SELECT 1 FROM students WHERE id = ? AND tenant_id = ?').get(studentId, tid);
    return !!row;
  }
  const row = await db
    .prepare(
      `SELECT 1 FROM students s JOIN leads l ON l.id = s.lead_id
       WHERE s.id = ? AND s.tenant_id = ? AND l.tenant_id = ? AND l.assigned_to = ?`
    )
    .get(studentId, tid, tid, req.user.id);
  return !!row;
}

/// Resolves the template to render with: an explicit `templateId` (if
/// given and it belongs to this tenant) or the tenant's default (created
/// lazily on first use). Shallow-merges its config over DEFAULT_TEMPLATE_CONFIG
/// so an older/partial template row still renders every section correctly
/// — a template only needs to override the fields it actually customizes.
async function resolveTemplate(tid, templateId) {
  let template = templateId
    ? await db.prepare('SELECT * FROM report_templates WHERE id = ? AND tenant_id = ?').get(templateId, tid)
    : null;
  if (!template) template = await getOrCreateDefaultTemplate(tid);
  const config = { ...DEFAULT_TEMPLATE_CONFIG, ...template.config, branding: { ...DEFAULT_TEMPLATE_CONFIG.branding, ...(template.config?.branding || {}) } };
  return { template, config };
}

async function fetchStudentMeta(studentId) {
  return db
    .prepare(
      `SELECT s.student_code, s.batch_year, s.course_name, s.institution_name,
              l.full_name, l.parent_phone, l.parent_relation, l.parent_name
       FROM students s JOIN leads l ON l.id = s.lead_id
       WHERE s.id = ?`
    )
    .get(studentId);
}

// GET /exams/groups — every exam sitting this tenant has imported marks
// for, most recent first. Lets the mobile "Report Cards" landing screen
// list past exams instead of requiring the exam's exact name to be typed
// again to look it up.
router.get('/groups', async (req, res) => {
  const tid = tenantId(req);
  const rows = await db
    .prepare(
      `SELECT a.exam_group, count(DISTINCT m.student_id) AS student_count, max(a.assessment_date) AS last_date
       FROM assessments a
       LEFT JOIN marks m ON m.assessment_id = a.id
       WHERE a.tenant_id = ? AND a.exam_group IS NOT NULL
       GROUP BY a.exam_group
       ORDER BY last_date DESC NULLS LAST`
    )
    .all(tid);
  return res.json(rows.map((r) => ({ examGroup: r.exam_group, studentCount: Number(r.student_count), lastDate: r.last_date })));
});

// POST /exams/import  (multipart: file=<xlsx>, fields: exam_group, mode, reason)
router.post('/import', upload.single('file'), async (req, res) => {
  const tid = tenantId(req);
  if (!req.file) return res.status(400).json({ error: 'file is required (.xlsx)' });
  const examGroup = req.body.exam_group;
  const mode = req.body.mode === 'amend' ? 'amend' : 'strict';
  if (!examGroup) return res.status(400).json({ error: 'exam_group is required' });

  let parsed;
  try {
    parsed = await parseMarksSheetBuffer(req.file.buffer);
  } catch (err) {
    return res.status(400).json({ error: `Could not parse sheet: ${err.message}` });
  }

  try {
    const result = await importMarks({
      tenantId: tid,
      examGroup,
      parsed,
      mode,
      reason: req.body.reason,
      recordedBy: req.user?.id || 'unknown',
    });
    await db
      .prepare(
        `INSERT INTO mark_imports (id, tenant_id, exam_group, file_name, mode, status, total_rows, imported_rows, blocked_reason, blocked_details, recorded_by)
         VALUES (gen_random_uuid(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(
        tid,
        examGroup,
        req.file.originalname,
        mode,
        result.blocked ? 'blocked' : 'completed',
        parsed.students.length,
        result.blocked ? 0 : (result.summary.inserted + result.summary.revised),
        result.blocked ? result.blockedReason : null,
        result.blocked ? JSON.stringify(result.blockedDetails) : null,
        req.user?.id || 'unknown'
      );

    if (result.blocked) return res.status(422).json(result);
    return res.json(result);
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }
});

// GET /exams/:examGroup/cohort — every student with at least one mark in
// this exam_group, ranked. Tenant-scoped; owner/admin see everyone, other
// roles see only their own assigned caseload (same rule as canAccessStudent,
// applied as a WHERE clause here instead of a per-row check).
router.get('/:examGroup/cohort', async (req, res) => {
  const tid = tenantId(req);
  const { examGroup } = req.params;

  const rows = await db
    .prepare(
      `SELECT st.id AS student_id, l.full_name, SUM(m.marks_obtained) AS total, l.assigned_to
       FROM marks m
       JOIN assessments a ON a.id = m.assessment_id
       JOIN students st ON st.id = m.student_id
       JOIN leads l ON l.id = st.lead_id
       WHERE a.tenant_id = ? AND a.exam_group = ? AND st.tenant_id = ? AND l.tenant_id = ?
       GROUP BY st.id, l.full_name, l.assigned_to
       ORDER BY total DESC`
    )
    .all(tid, examGroup, tid, tid);

  const visible = req.user && ['owner', 'admin'].includes(req.user.role)
    ? rows
    : rows.filter((r) => r.assigned_to === req.user?.id);

  return res.json(
    visible.map((r, i) => ({ studentId: r.student_id, name: r.full_name, total: Number(r.total), rank: i + 1 }))
  );
});

// GET /exams/:examGroup/students/:studentId/report — compute figures +
// narrative, does not render an image or send anything.
router.get('/:examGroup/students/:studentId/report', async (req, res) => {
  const tid = tenantId(req);
  const { examGroup, studentId } = req.params;
  if (!(await canAccessStudent(req, studentId))) {
    return res.status(404).json({ error: 'Student not found' }); // 404, not 403 — don't confirm existence outside scope
  }
  try {
    const summary = await computeReportCard(tid, studentId, examGroup);
    const meta = await fetchStudentMeta(studentId);
    const { narrative, isFallback } = await generateNarrative(summary, meta.full_name);
    const existingCard = await db
      .prepare('SELECT teacher_remark FROM report_cards WHERE tenant_id = ? AND student_id = ? AND exam_group = ?')
      .get(tid, studentId, examGroup);
    return res.json({
      summary,
      narrative,
      narrativeIsFallback: isFallback,
      teacherRemark: existingCard?.teacher_remark || null,
      studentMeta: {
        name: meta.full_name,
        studentCode: meta.student_code,
        batch: meta.batch_year,
        course: meta.course_name,
        institution: meta.institution_name,
        parentName: meta.parent_name,
        parentRelation: meta.parent_relation,
      },
    });
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }
});

// POST /exams/:examGroup/students/:studentId/generate — computes, renders
// the image, uploads it (private bucket, signed URL), saves a report_cards
// row with status='ready'. Does not send anything yet.
router.post('/:examGroup/students/:studentId/generate', async (req, res) => {
  const tid = tenantId(req);
  const { examGroup, studentId } = req.params;
  if (!(await canAccessStudent(req, studentId))) {
    return res.status(404).json({ error: 'Student not found' });
  }
  try {
    const summary = await computeReportCard(tid, studentId, examGroup);
    const meta = await fetchStudentMeta(studentId);
    const { narrative, isFallback } = await generateNarrative(summary, meta.full_name);
    const { template, config } = await resolveTemplate(tid, req.body.template_id);
    // A teacher's own written remark, distinct from the computed/AI
    // narrative -- omitting it on a regenerate (e.g. after correcting a
    // mark) keeps whatever remark was already saved rather than blanking it.
    const teacherRemark = req.body.teacher_remark !== undefined ? (req.body.teacher_remark || null) : null;
    const png = await renderReportCardPng(summary, {
      studentName: meta.full_name,
      narrative,
      teacherRemark,
      template: config,
      studentMeta: {
        studentCode: meta.student_code,
        batch: meta.batch_year,
        course: meta.course_name,
        institution: meta.institution_name,
      },
    });

    const storagePath = `report-cards/${tid}/${studentId}-${examGroup.replace(/[^a-z0-9]/gi, '_')}.png`;
    await uploadFile(png, storagePath, 'image/png');

    // The guardian's phone always comes from the lead record fresh — never
    // from anything the sheet import might have parsed — so it reflects
    // whatever the counselor has most recently corrected in the CRM.
    const guardian = normalizeGuardianPhone(meta.parent_phone);

    const row = await db
      .prepare(
        `INSERT INTO report_cards (id, tenant_id, student_id, exam_group, template_id, computed_summary, ai_narrative, ai_narrative_is_fallback, teacher_remark, image_storage_path, status, generated_at, generated_by)
         VALUES (gen_random_uuid(), ?, ?, ?, ?, ?, ?, ?, ?, ?, 'ready', now(), ?)
         ON CONFLICT (student_id, exam_group) DO UPDATE SET
           template_id = EXCLUDED.template_id,
           computed_summary = EXCLUDED.computed_summary,
           ai_narrative = EXCLUDED.ai_narrative,
           ai_narrative_is_fallback = EXCLUDED.ai_narrative_is_fallback,
           teacher_remark = COALESCE(EXCLUDED.teacher_remark, report_cards.teacher_remark),
           image_storage_path = EXCLUDED.image_storage_path,
           status = 'ready', generated_at = now(), generated_by = EXCLUDED.generated_by,
           updated_at = now()
         RETURNING id, teacher_remark`
      )
      .get(tid, studentId, examGroup, template.id, JSON.stringify(summary), narrative, isFallback, teacherRemark, storagePath, req.user?.id || 'unknown');

    // Everything the coordinator needs to review before sending — nothing
    // here should require re-typing anything already on file.
    return res.json({
      reportCardId: row.id,
      summary,
      narrative,
      narrativeIsFallback: isFallback,
      teacherRemark: row.teacher_remark,
      templateId: template.id,
      templateName: template.name,
      studentMeta: {
        name: meta.full_name,
        studentCode: meta.student_code,
        batch: meta.batch_year,
        course: meta.course_name,
        institution: meta.institution_name,
      },
      parentName: meta.parent_name || (meta.parent_relation ? `${meta.parent_relation}` : 'Parent/Guardian'),
      guardianPhone: guardian.number,
      guardianPhoneSuspect: guardian.suspect,
      guardianPhoneReason: guardian.reason || null,
    });
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }
});

// POST /exams/:examGroup/students/:studentId/send — requires the caller to
// have explicitly confirmed the guardian number (`confirmed: true` in the
// body). Re-fetches the guardian record fresh at send time — never trusts
// a phone number the client cached from an earlier /generate call — per
// the reference implementation's "sending to the wrong parent is the worst
// thing this feature can do, so it is guarded" rule.
router.post('/:examGroup/students/:studentId/send', async (req, res) => {
  const tid = tenantId(req);
  const { examGroup, studentId } = req.params;
  if (!(await canAccessStudent(req, studentId))) {
    return res.status(404).json({ error: 'Student not found' });
  }
  if (req.body.confirmed !== true) {
    return res.status(400).json({ error: 'Set confirmed: true after a human has read the guardian number' });
  }

  const card = await db
    .prepare('SELECT * FROM report_cards WHERE tenant_id = ? AND student_id = ? AND exam_group = ?')
    .get(tid, studentId, examGroup);
  if (!card || card.status === 'draft') {
    return res.status(400).json({ error: 'Generate the report card first (POST .../generate)' });
  }

  const lead = await db
    .prepare('SELECT l.full_name, l.parent_phone FROM students s JOIN leads l ON l.id = s.lead_id WHERE s.id = ?')
    .get(studentId);
  const guardian = normalizeGuardianPhone(req.body.phone_override || lead.parent_phone);
  if (!guardian.number) {
    return res.status(400).json({ error: 'No usable guardian phone number on file' });
  }

  try {
    const signedUrl = await getSignedUrl(card.image_storage_path, 300);
    await sendWhatsAppImage(guardian.number, signedUrl, `${lead.full_name}'s ${examGroup} report card`);

    await db.transaction(async (tx) => {
      await tx
        .prepare(`UPDATE report_cards SET status = 'sent', sent_at = now(), sent_to_phone = ? WHERE id = ?`)
        .run(guardian.number, card.id);
      await tx
        .prepare(
          `INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
           VALUES (gen_random_uuid(), ?, (SELECT lead_id FROM students WHERE id = ?), 'whatsapp', 'outbound', ?, ?)`
        )
        .run(tid, studentId, `Report card sent: ${examGroup}`, req.user?.id || 'unknown');
    });

    return res.json({ sent: true, to: guardian.number });
  } catch (err) {
    return res.status(400).json({ error: `Send failed: ${err.message}` });
  }
});

// GET /exams/:examGroup/students/:studentId/whatsapp-link?guardian=father|mother
// FREE, semi-automatic method — no Meta Cloud API, no cost, no approval
// needed. Same wa.me "click to chat" pattern already used for leads
// (routes/whatsappLink.js) and flyers (routes/flyerProjects.js's
// /share-link): a human still taps Send in WhatsApp. The report card image
// can't be attached to a wa.me link directly (text only), so the message
// carries a long-lived (7-day, same trade-off flyerProjects.js already made
// for a link a parent may open hours later) signed link to it instead.
// This is deliberately separate from POST .../send below — that one calls
// the Meta Cloud API directly (sendWhatsAppImage) and is the future paid-tier
// path once WHATSAPP_TOKEN/WHATSAPP_PHONE_NUMBER_ID are actually configured;
// this route needs neither and is today's real send path.
router.get('/:examGroup/students/:studentId/whatsapp-link', async (req, res) => {
  const tid = tenantId(req);
  const { examGroup, studentId } = req.params;
  const guardian = req.query.guardian === 'mother' ? 'mother' : 'father';
  if (!(await canAccessStudent(req, studentId))) {
    return res.status(404).json({ error: 'Student not found' });
  }

  const card = await db
    .prepare('SELECT * FROM report_cards WHERE tenant_id = ? AND student_id = ? AND exam_group = ?')
    .get(tid, studentId, examGroup);
  if (!card || card.status === 'draft') {
    return res.status(400).json({ error: 'Generate the report card first (POST .../generate)' });
  }

  const lead = await db
    .prepare(
      `SELECT l.full_name, l.father_name, l.father_phone, l.mother_name, l.mother_phone
       FROM students s JOIN leads l ON l.id = s.lead_id WHERE s.id = ?`
    )
    .get(studentId);
  const guardianName = guardian === 'mother' ? lead.mother_name : lead.father_name;
  const guardianPhone = guardian === 'mother' ? lead.mother_phone : lead.father_phone;
  if (!guardianPhone) {
    return res.status(400).json({ error: `No ${guardian}'s phone number on file for this student` });
  }

  const SEVEN_DAYS = 7 * 24 * 60 * 60;
  let imageUrl;
  try {
    imageUrl = await getSignedUrl(card.image_storage_path, SEVEN_DAYS);
  } catch (err) {
    return res.status(502).json({ error: `Could not create share link: ${err.message}` });
  }

  const tenant = await db.prepare('SELECT default_country_code FROM tenants WHERE id = ?').get(tid);
  const greeting = (req.body && req.body.message) || `Hi${guardianName ? ' ' + guardianName : ''}, sharing ${lead.full_name}'s ${examGroup} report card with you.`;
  const message = `${greeting}\n\n${imageUrl}`;
  const link = buildWhatsAppLink(guardianPhone, null, message, tenant && tenant.default_country_code);
  if (!link) return res.status(400).json({ error: `Could not build a WhatsApp link for ${guardian}'s number on file` });

  return res.json({
    whatsapp_link: link,
    image_url: imageUrl,
    guardian,
    guardian_name: guardianName,
    message,
    expires_in_days: 7,
  });
});

// POST /exams/:examGroup/students/:studentId/whatsapp-link/confirm-sent
// Call this after the counselor taps Send in WhatsApp, to log it in
// Communication Hub and mark the report card sent — the free wa.me method
// has no delivery webhook of its own, same limitation whatsappLink.js
// already documents for lead chat-links.
router.post('/:examGroup/students/:studentId/whatsapp-link/confirm-sent', async (req, res) => {
  const tid = tenantId(req);
  const { examGroup, studentId } = req.params;
  const guardian = req.body.guardian === 'mother' ? 'mother' : 'father';
  if (!(await canAccessStudent(req, studentId))) {
    return res.status(404).json({ error: 'Student not found' });
  }

  const card = await db
    .prepare('SELECT id FROM report_cards WHERE tenant_id = ? AND student_id = ? AND exam_group = ?')
    .get(tid, studentId, examGroup);
  if (!card) return res.status(400).json({ error: 'Generate the report card first (POST .../generate)' });

  await db.transaction(async (tx) => {
    await tx
      .prepare(`UPDATE report_cards SET status = 'sent', sent_at = now(), sent_to_phone = ? WHERE id = ?`)
      .run(req.body.phone || null, card.id);
    await tx
      .prepare(
        `INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
         VALUES (gen_random_uuid(), ?, (SELECT lead_id FROM students WHERE id = ?), 'whatsapp-link', 'outbound', ?, ?)`
      )
      .run(tid, studentId, `Report card sent to ${guardian}: ${examGroup}`, req.user?.id || 'unknown');
  });

  return res.status(201).json({ logged: true });
});

// PATCH /exams/marks/:markId — amend a single mark (reason required).
// Never a silent overwrite: logs mark_revisions before updating. A mark
// above its assessment's max is refused outright.
router.patch('/marks/:markId', async (req, res) => {
  const tid = tenantId(req);
  const { markId } = req.params;
  const { new_value: newValue, reason } = req.body;
  if (newValue === undefined || !reason) {
    return res.status(400).json({ error: 'new_value and reason are required' });
  }

  const mark = await db
    .prepare(
      `SELECT m.id, m.marks_obtained, m.student_id, a.max_marks
       FROM marks m JOIN assessments a ON a.id = m.assessment_id
       WHERE m.id = ? AND m.tenant_id = ?`
    )
    .get(markId, tid);
  if (!mark) return res.status(404).json({ error: 'Mark not found' });
  if (!(await canAccessStudent(req, mark.student_id))) {
    return res.status(404).json({ error: 'Mark not found' });
  }
  if (Number(newValue) > Number(mark.max_marks)) {
    return res.status(422).json({ error: `${newValue} exceeds this assessment's max of ${mark.max_marks}` });
  }

  await db.transaction(async (tx) => {
    await tx
      .prepare(
        `INSERT INTO mark_revisions (id, tenant_id, mark_id, student_id, previous_value, new_value, reason, revised_by)
         VALUES (gen_random_uuid(), ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(tid, mark.id, mark.student_id, mark.marks_obtained, newValue, reason, req.user?.id || 'unknown');
    await tx.prepare('UPDATE marks SET marks_obtained = ?, updated_at = now() WHERE id = ?').run(newValue, mark.id);
  });

  return res.json({ updated: true });
});

// PATCH /exams/subjects/:subjectId — free edit (name/code are labels; no
// revision log needed, unlike an assessment's max_marks).
router.patch('/subjects/:subjectId', async (req, res) => {
  const tid = tenantId(req);
  const { subjectId } = req.params;
  const allowed = ['name', 'code', 'phase_or_semester', 'credit_hours', 'active'];
  const changes = Object.fromEntries(Object.entries(req.body).filter(([k]) => allowed.includes(k)));
  if (!Object.keys(changes).length) {
    return res.status(400).json({ error: `No editable fields provided (allowed: ${allowed.join(', ')})` });
  }
  const subject = await db.prepare('SELECT id FROM subjects WHERE id = ? AND tenant_id = ?').get(subjectId, tid);
  if (!subject) return res.status(404).json({ error: 'Subject not found' });

  const setClauses = Object.keys(changes).map((k) => `${k} = ?`).join(', ');
  await db.prepare(`UPDATE subjects SET ${setClauses}, updated_at = now() WHERE id = ?`).run(...Object.values(changes), subjectId);
  return res.json({ updated: true });
});

// PATCH /exams/assessments/:assessmentId — see examIntelligence.updateAssessment
// for the guard: max_marks/passing_marks changes need `confirmed: true` +
// `reason` once marks already exist, and reset any not-yet-sent report
// cards in that exam_group back to 'draft'.
router.patch('/assessments/:assessmentId', async (req, res) => {
  const tid = tenantId(req);
  const { assessmentId } = req.params;
  const allowed = ['name', 'max_marks', 'passing_marks', 'weight_percent', 'assessment_date'];
  const { confirmed, reason, ...body } = req.body;
  const changes = Object.fromEntries(Object.entries(body).filter(([k]) => allowed.includes(k)));
  if (!Object.keys(changes).length) {
    return res.status(400).json({ error: `No editable fields provided (allowed: ${allowed.join(', ')})` });
  }
  try {
    const result = await updateAssessment(tid, assessmentId, changes, { confirmed, reason, revisedBy: req.user?.id || 'unknown' });
    if (result.blocked) return res.status(409).json(result);
    return res.json(result);
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }
});

// --- Report templates -------------------------------------------------
// A real per-tenant customization point, not a fixed layout. GET always
// returns at least one row (the default is created lazily on first call).

// GET /exams/templates
router.get('/templates', async (req, res) => {
  const tid = tenantId(req);
  await getOrCreateDefaultTemplate(tid); // ensures at least the default exists
  const rows = await db.prepare('SELECT * FROM report_templates WHERE tenant_id = ? ORDER BY is_default DESC, name').all(tid);
  return res.json(rows);
});

// POST /exams/templates — create a new template, typically a clone of an
// existing one with `config` overridden (the client fetches a template via
// GET, edits the config client-side, and POSTs the result as a new named
// template — cloning, not rebuilding from scratch every time).
router.post('/templates', async (req, res) => {
  const tid = tenantId(req);
  const { name, config } = req.body;
  if (!name || !config) return res.status(400).json({ error: 'name and config are required' });
  const row = await db
    .prepare('INSERT INTO report_templates (id, tenant_id, name, config, is_default) VALUES (gen_random_uuid(), ?, ?, ?, false) RETURNING *')
    .get(tid, name, JSON.stringify(config));
  return res.json(row);
});

// PATCH /exams/templates/:id
router.patch('/templates/:id', async (req, res) => {
  const tid = tenantId(req);
  const { id } = req.params;
  const template = await db.prepare('SELECT id FROM report_templates WHERE id = ? AND tenant_id = ?').get(id, tid);
  if (!template) return res.status(404).json({ error: 'Template not found' });

  const fields = [];
  const values = [];
  if (req.body.name !== undefined) { fields.push('name'); values.push(req.body.name); }
  if (req.body.config !== undefined) { fields.push('config'); values.push(JSON.stringify(req.body.config)); }
  if (req.body.is_default === true) { fields.push('is_default'); values.push(true); }
  if (!fields.length) return res.status(400).json({ error: 'Nothing to update' });

  await db.transaction(async (tx) => {
    if (req.body.is_default === true) {
      // Only one default per tenant — matches getOrCreateDefaultTemplate's
      // own assumption (LIMIT 1 on is_default = true).
      await tx.prepare('UPDATE report_templates SET is_default = false WHERE tenant_id = ? AND id != ?').run(tid, id);
    }
    const setClauses = fields.map((f) => `${f} = ?`).join(', ');
    await tx.prepare(`UPDATE report_templates SET ${setClauses}, updated_at = now() WHERE id = ?`).run(...values, id);
  });
  return res.json({ updated: true });
});

// POST /exams/templates/preview — renders a template config (not necessarily
// saved yet) against either a real student's real marks (student_id +
// exam_group) or built-in sample data, WITHOUT the AI narrative call,
// storage upload, or report_cards write that POST .../generate does —
// cheap enough to call on every edit in the template editor, so the preview
// is a real rendered PNG (WYSIWYG) rather than a client-side mock.
const SAMPLE_PREVIEW_SUMMARY = {
  examGroup: 'Sample Exam',
  subjects: [
    { subject: 'ANATOMY', marksObtained: 78, maxMarks: 100, percentage: 78 },
    { subject: 'PHYSIOLOGY', marksObtained: 84, maxMarks: 100, percentage: 84 },
    { subject: 'BIOCHEMISTRY', marksObtained: 65, maxMarks: 100, percentage: 65 },
  ],
  total: 227,
  maxTotal: 300,
  overallPercentage: 75.7,
  overallGrade: 'B+',
  rank: 3,
  cohortSize: 42,
  batchAverage: 210,
  previousDelta: { comparedTo: 'Previous Exam', previousPercentage: 71, change: 4.7 },
};

router.post('/templates/preview', async (req, res) => {
  const tid = tenantId(req);
  const { config = {}, student_id: studentId, exam_group: examGroup } = req.body;
  const mergedConfig = {
    ...DEFAULT_TEMPLATE_CONFIG,
    ...config,
    branding: { ...DEFAULT_TEMPLATE_CONFIG.branding, ...(config.branding || {}) },
  };

  let summary = SAMPLE_PREVIEW_SUMMARY;
  let studentName = 'Sample Student';
  let studentMeta = { studentCode: 'SMP-001', batch: '2026', course: 'Sample Course', institution: 'Sample Institution' };
  let narrative = 'This is a sample computed summary shown for preview only.';

  if (studentId && examGroup) {
    if (!(await canAccessStudent(req, studentId))) {
      return res.status(404).json({ error: 'Student not found' });
    }
    try {
      summary = await computeReportCard(tid, studentId, examGroup);
    } catch (err) {
      return res.status(400).json({ error: err.message });
    }
    const meta = await fetchStudentMeta(studentId);
    studentName = meta.full_name;
    studentMeta = { studentCode: meta.student_code, batch: meta.batch_year, course: meta.course_name, institution: meta.institution_name };
    narrative = 'Preview only — the real report uses a computed or AI-written narrative.';
  }

  try {
    const png = await renderReportCardPng(summary, { studentName, narrative, template: mergedConfig, studentMeta });
    res.set('Content-Type', 'image/png');
    return res.send(png);
  } catch (err) {
    return res.status(400).json({ error: `Could not render preview: ${err.message}` });
  }
});

module.exports = router;
