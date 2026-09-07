// Exam Intelligence + Report Card System — core logic.
//
// Ported into leadflow-ai's own stack (Node/Express + Postgres + Flutter)
// rather than left on the separate nepalmbbs-website branch it was first
// built against. Reuses leadflow-ai's existing `students`/`subjects`/
// `assessments`/`marks` tables (they existed, unused, before this file) and
// its existing `leads.parent_name`/`parent_phone`/`parent_relation` as the
// guardian contact — no new `guardians`/`institutions` table was added.
//
// Ground rules carried over from the reference implementation (see this
// repo's DECISION_LOG.md, 2026-09-06 entry, for the full rationale):
//   - Every figure a report card shows is computed here in plain code from
//     `marks`/`assessments`, never invented by the AI model.
//   - A subject with no max_marks blocks the import and asks, rather than
//     guessing a split.
//   - A corrected mark is a logged conflict (`mark_revisions`), never a
//     silent overwrite. A mark above its max is refused outright.
//   - A guardian's phone is normalized only where the pattern is
//     unambiguous; anything else is flagged `suspect`, never repaired.
//   - The AI narrative's own numbers are checked against the computed
//     figures before being shown; a mismatch (or no provider configured)
//     falls back to a plain computed sentence that says so.

const readXlsxFile = require('read-excel-file/node');
const db = require('../db');
const { generateText, generateJson } = require('./aiProvider');
const { digitsOnly, toWhatsAppNumber } = require('./phone');

// ---------------------------------------------------------------------------
// Sheet format — confirmed against a real college result sheet (Chitwan
// Medical College, MBBS 1st year 2nd internal assessment), inspected for
// header structure only (never student data), so this parses the actual
// shape colleges export rather than a simplified guess:
//
//   Row 1-3   free-text title block (college/exam name/dates) — ignored.
//             Not assumed to be exactly 3 rows; the header row is found by
//             scanning for a "Student Name" cell, whatever row it's on.
//   Row above the header: PAPER-GROUP row. A paper's name+total appears
//             once (e.g. "IBMS-MSK(120/60)") in a merged cell spanning all
//             of that paper's subject/Total/Result columns; the reader
//             sees the other cells in that span as blank, so this row is
//             forward-filled left-to-right before use.
//   Header row: metadata columns (S.N., Batch, Student ID, Category, ...),
//             then per-paper: one column per subject — named either
//             "SUBJECT(max)" (max stated inline, e.g. "ANA(20)") or just
//             "SUBJECT" with no max at all — followed by that paper's own
//             "Total(N)" and "Result" columns. Repeats per paper. May be
//             followed by "Father's Name" / "Cell Number" / "Mother's
//             Name" / "Cell Number" (two columns can share the exact same
//             header text) at the end.
//   Data rows: one per student, aligned to the header row's columns.
//
// "Father's Name"/"Cell Number"/"Mother's Name"/"Cell Number" ARE extracted
// (2026-09-07 — the WhatsApp-hyperlink report-card feature needs both
// guardians' numbers, not just the single leads.parent_phone this sheet
// import originally deferred to). "Cell Number" appears twice with the
// identical header text, so the two occurrences are told apart positionally
// — whichever guardian-name column most recently preceded a "Cell Number"
// column owns it, matching the real sheet's left-to-right layout. Backfilled
// onto the matched lead's father_name/father_phone/mother_name/mother_phone
// only when those columns are currently empty (see resolveStudents) — never
// overwrites a value a counselor already corrected in the CRM, same rule as
// parent_phone.
//
// "Student Code" is matched first when present; otherwise the student is
// matched by exact, case-insensitive `full_name` within the tenant's leads
// (see resolveStudents below) — "Student ID" in the real sheet is treated
// as this code.
// ---------------------------------------------------------------------------

const IGNORED_HEADER_COLS = /^(s\.?n\.?|batch|category|total\s*(\(|$)|result)/i;
const FATHER_NAME_RE = /^father'?s?\s*name$/i;
const MOTHER_NAME_RE = /^mother'?s?\s*name$/i;
const CELL_NUMBER_RE = /^cell\s*number$/i;

/// Walks the header left-to-right once, associating each "Cell Number"
/// column with whichever guardian-name column most recently preceded it
/// (both share the exact same "Cell Number" text, so order is the only
/// signal). Returns column indices only — undefined for any not present.
function findGuardianCols(header) {
  const cols = {};
  let current = null;
  header.forEach((h, i) => {
    const text = String(h ?? '').trim();
    if (FATHER_NAME_RE.test(text)) {
      cols.fatherNameCol = i;
      current = 'father';
    } else if (MOTHER_NAME_RE.test(text)) {
      cols.motherNameCol = i;
      current = 'mother';
    } else if (CELL_NUMBER_RE.test(text) && current) {
      cols[`${current}PhoneCol`] = i;
    }
  });
  return cols;
}

/// "ANA(20)" -> { name: "ANA", max: 20 }. "HP&E" (no parenthetical, or one
/// that isn't a single plain number like a paper's "(120/60)") -> max: null.
function extractSubjectAndMax(headerCell) {
  const text = String(headerCell ?? '').trim();
  const m = text.match(/^(.*?)\((\d+(?:\.\d+)?)\)\s*$/);
  if (m) return { name: m[1].trim(), max: Number(m[2]) };
  return { name: text, max: null };
}

/// Carries the last non-blank value rightward across a row — undoes what a
/// merged cell looks like once read as plain values (the value lives only
/// in the merge's anchor cell; every other cell in the span reads blank).
function forwardFill(row) {
  const filled = [];
  let last = null;
  for (const cell of row || []) {
    const text = cell === null || cell === undefined ? '' : String(cell).trim();
    if (text !== '') last = text;
    filled.push(last);
  }
  return filled;
}

function findHeaderRowIndex(rows) {
  for (let i = 0; i < rows.length; i++) {
    if ((rows[i] || []).some((c) => /student\s*name/i.test(String(c ?? '')))) return i;
  }
  throw new Error('Could not find a header row containing a "Student Name" column');
}

function parseMarksSheetBuffer(buffer) {
  return readXlsxFile(buffer).then((parsed) => {
    // This version of read-excel-file returns [{ sheet, data }, ...]
    // rather than a flat row array — same quirk already handled in
    // routes/leadsImportExcel.js; use the first sheet's data either way.
    const rows = Array.isArray(parsed) && parsed.length > 0 && parsed[0] && parsed[0].data
      ? parsed[0].data
      : parsed;
    if (!rows || rows.length < 2) {
      throw new Error('File is empty or unreadable');
    }
    const headerRowIdx = findHeaderRowIndex(rows);
    const paperGroupRow = headerRowIdx > 0 ? forwardFill(rows[headerRowIdx - 1]) : [];
    const header = (rows[headerRowIdx] || []).map((h) => String(h ?? '').trim());

    const nameColIdx = header.findIndex((h) => /^student\s*name$/i.test(h));
    if (nameColIdx === -1) throw new Error('No "Student Name" column found on the header row');
    const codeColIdx = header.findIndex((h) => /^student\s*(id|code)$/i.test(h));
    const guardianCols = findGuardianCols(header);
    const guardianColIdxSet = new Set(Object.values(guardianCols));

    const subjectCols = [];
    header.forEach((h, i) => {
      if (i === nameColIdx || i === codeColIdx || guardianColIdxSet.has(i) || !h || IGNORED_HEADER_COLS.test(h)) return;
      const { name, max } = extractSubjectAndMax(h);
      if (!name) return;
      subjectCols.push({ colIdx: i, subjectName: name, maxMarks: max, paperGroup: paperGroupRow[i] || null });
    });
    if (!subjectCols.length) {
      throw new Error('No subject columns found — expected columns like "ANA(20)" after the metadata columns');
    }

    const subjectNames = subjectCols.map((c) => c.subjectName);
    const maxBySubject = {};
    const paperGroupBySubject = {};
    subjectCols.forEach((c) => {
      maxBySubject[c.subjectName] = c.maxMarks;
      paperGroupBySubject[c.subjectName] = c.paperGroup;
    });

    const dataRows = rows
      .slice(headerRowIdx + 1)
      .filter((r) => r[nameColIdx] !== null && r[nameColIdx] !== undefined && String(r[nameColIdx]).trim() !== '');
    const students = dataRows.map((r) => {
      const marksBySubject = {};
      subjectCols.forEach((c) => {
        const val = r[c.colIdx];
        marksBySubject[c.subjectName] = val === null || val === undefined || val === '' ? null : Number(val);
      });
      const cell = (colIdx) => (colIdx === undefined || r[colIdx] === null || r[colIdx] === undefined ? null : String(r[colIdx]).trim() || null);
      return {
        name: String(r[nameColIdx]).trim(),
        code: codeColIdx === -1 ? null : (r[codeColIdx] ? String(r[codeColIdx]).trim() : null),
        marksBySubject,
        fatherName: cell(guardianCols.fatherNameCol),
        fatherPhone: cell(guardianCols.fatherPhoneCol),
        motherName: cell(guardianCols.motherNameCol),
        motherPhone: cell(guardianCols.motherPhoneCol),
      };
    });

    return { subjectNames, maxBySubject, paperGroupBySubject, students };
  });
}

/// Blocks the import outright if any subject has no stated max, quoting the
/// highest mark seen in that column as a hint — mirrors the reference
/// implementation's refusal to guess.
function findMissingMaxSubjects(parsed) {
  const missing = [];
  for (const name of parsed.subjectNames) {
    if (parsed.maxBySubject[name] === null) {
      const seen = parsed.students
        .map((s) => s.marksBySubject[name])
        .filter((v) => v !== null && !Number.isNaN(v));
      missing.push({
        subject: name,
        highestMarkSeen: seen.length ? Math.max(...seen) : null,
      });
    }
  }
  return missing;
}

/// A mark above its own subject's max is refused outright, never clamped.
function findOutOfRangeMarks(parsed) {
  const problems = [];
  for (const student of parsed.students) {
    for (const name of parsed.subjectNames) {
      const max = parsed.maxBySubject[name];
      const val = student.marksBySubject[name];
      if (max !== null && val !== null && val > max) {
        problems.push({ student: student.name, subject: name, marks: val, max });
      }
    }
  }
  return problems;
}

/// Resolves each sheet row to an existing student (by code, then by exact
/// case-insensitive lead name within the tenant). Never auto-creates a
/// lead/student from a spreadsheet name — an unmatched row blocks with a
/// clear reason instead of silently inventing a record.
async function resolveStudents(tenantId, parsed) {
  const resolved = [];
  const unmatched = [];
  for (const row of parsed.students) {
    let student = null;
    if (row.code) {
      student = await db
        .prepare('SELECT id, lead_id FROM students WHERE tenant_id = ? AND student_code = ?')
        .get(tenantId, row.code);
    }
    if (!student) {
      student = await db
        .prepare(
          `SELECT st.id, st.lead_id FROM students st
           JOIN leads l ON l.id = st.lead_id
           WHERE st.tenant_id = ? AND lower(l.full_name) = lower(?)`
        )
        .get(tenantId, row.name);
    }
    if (student) {
      resolved.push({ ...row, studentId: student.id, leadId: student.lead_id });
    } else {
      unmatched.push(row.name);
    }
  }
  return { resolved, unmatched };
}

/// Imports one exam_group's marks for one tenant. `mode` is 'strict' (only
/// writes where no mark exists yet, reports the rest untouched) or 'amend'
/// (requires `reason`; every changed value is logged to mark_revisions
/// before the update, never overwritten silently). Runs as one transaction
/// — either the whole batch lands or none of it does.
async function importMarks({ tenantId, examGroup, parsed, mode, reason, recordedBy }) {
  if (mode === 'amend' && !reason) {
    throw new Error('An amend import requires a written reason');
  }

  const missingMax = findMissingMaxSubjects(parsed);
  if (missingMax.length) {
    return { blocked: true, blockedReason: 'subjects missing a max mark', blockedDetails: missingMax };
  }
  const outOfRange = findOutOfRangeMarks(parsed);
  if (outOfRange.length) {
    return { blocked: true, blockedReason: 'marks above their subject\'s max', blockedDetails: outOfRange };
  }

  const { resolved, unmatched } = await resolveStudents(tenantId, parsed);
  if (unmatched.length) {
    return { blocked: true, blockedReason: 'students not found in this tenant', blockedDetails: unmatched };
  }

  const summary = { inserted: 0, unchanged: 0, revised: 0 };

  await db.transaction(async (tx) => {
    for (const name of parsed.subjectNames) {
      let subject = await tx
        .prepare('SELECT id FROM subjects WHERE tenant_id = ? AND lower(name) = lower(?)')
        .get(tenantId, name);
      if (!subject) {
        subject = await tx
          .prepare('INSERT INTO subjects (id, tenant_id, name, active) VALUES (gen_random_uuid(), ?, ?, true) RETURNING id')
          .get(tenantId, name);
      }

      let assessment = await tx
        .prepare('SELECT id, max_marks FROM assessments WHERE tenant_id = ? AND subject_id = ? AND exam_group = ?')
        .get(tenantId, subject.id, examGroup);
      if (!assessment) {
        assessment = await tx
          .prepare(
            `INSERT INTO assessments (id, tenant_id, subject_id, name, assessment_type, max_marks, exam_group)
             VALUES (gen_random_uuid(), ?, ?, ?, 'internal', ?, ?) RETURNING id, max_marks`
          )
          .get(tenantId, subject.id, examGroup, parsed.maxBySubject[name], examGroup);
      }

      for (const student of resolved) {
        const marksObtained = student.marksBySubject[name];
        if (marksObtained === null) continue;

        const existing = await tx
          .prepare('SELECT id, marks_obtained FROM marks WHERE assessment_id = ? AND student_id = ?')
          .get(assessment.id, student.studentId);

        if (!existing) {
          await tx
            .prepare(
              `INSERT INTO marks (id, tenant_id, student_id, assessment_id, marks_obtained, source, recorded_by)
               VALUES (gen_random_uuid(), ?, ?, ?, ?, 'import', ?)`
            )
            .run(tenantId, student.studentId, assessment.id, marksObtained, recordedBy);
          summary.inserted++;
        } else if (Number(existing.marks_obtained) === Number(marksObtained)) {
          summary.unchanged++;
        } else if (mode === 'strict') {
          summary.unchanged++;
        } else {
          await tx
            .prepare(
              `INSERT INTO mark_revisions (id, tenant_id, mark_id, student_id, previous_value, new_value, reason, revised_by)
               VALUES (gen_random_uuid(), ?, ?, ?, ?, ?, ?, ?)`
            )
            .run(tenantId, existing.id, student.studentId, existing.marks_obtained, marksObtained, reason, recordedBy);
          await tx
            .prepare('UPDATE marks SET marks_obtained = ?, updated_at = now() WHERE id = ?')
            .run(marksObtained, existing.id);
          summary.revised++;
        }
      }
    }

    // Backfill father/mother name+phone onto the lead, sheet-provided value
    // only where the CRM's own column is still empty — never overwrites
    // something a counselor already entered/corrected, same rule as
    // parent_phone elsewhere in this file.
    for (const student of resolved) {
      if (!student.fatherName && !student.fatherPhone && !student.motherName && !student.motherPhone) continue;
      await tx
        .prepare(
          `UPDATE leads SET
             father_name = COALESCE(father_name, ?),
             father_phone = COALESCE(father_phone, ?),
             mother_name = COALESCE(mother_name, ?),
             mother_phone = COALESCE(mother_phone, ?),
             updated_at = to_char(now(), 'YYYY-MM-DD HH24:MI:SS')
           WHERE id = ? AND tenant_id = ?`
        )
        .run(student.fatherName, student.fatherPhone, student.motherName, student.motherPhone, student.leadId, tenantId);
    }
  });

  return { blocked: false, summary };
}

const GRADE_BANDS = [
  { min: 90, grade: 'A+' },
  { min: 80, grade: 'A' },
  { min: 70, grade: 'B+' },
  { min: 60, grade: 'B' },
  { min: 50, grade: 'C' },
  { min: 40, grade: 'D' },
  { min: 0, grade: 'F' },
];

/// Deterministic, not AI-derived. Default bands — a tenant that needs its
/// own scale should get one via `report_templates.config`, not by asking
/// the model to grade anything (not built in this pass; see NEXT_TASK.md).
function gradeFor(percentage) {
  return GRADE_BANDS.find((b) => percentage >= b.min).grade;
}

/// Computes every figure the report card shows. Pure SQL + arithmetic — no
/// AI call in this function, by design.
async function computeReportCard(tenantId, studentId, examGroup) {
  const rows = await db
    .prepare(
      `SELECT s.id AS subject_id, s.name AS subject_name, a.id AS assessment_id, a.max_marks, a.passing_marks,
              m.id AS mark_id, m.marks_obtained
       FROM assessments a
       JOIN subjects s ON s.id = a.subject_id
       LEFT JOIN marks m ON m.assessment_id = a.id AND m.student_id = ?
       WHERE a.tenant_id = ? AND a.exam_group = ?
       ORDER BY s.name`
    )
    .all(studentId, tenantId, examGroup);

  if (!rows.length) {
    throw new Error(`No assessments found for exam_group "${examGroup}" in this tenant`);
  }

  const subjects = rows.map((r) => {
    const obtained = r.marks_obtained === null ? null : Number(r.marks_obtained);
    const max = Number(r.max_marks);
    return {
      subject: r.subject_name,
      subjectId: r.subject_id,
      assessmentId: r.assessment_id,
      markId: r.mark_id,
      marksObtained: obtained,
      maxMarks: max,
      percentage: obtained === null ? null : Math.round((obtained / max) * 1000) / 10,
      passed: obtained === null ? null : (r.passing_marks === null ? null : obtained >= Number(r.passing_marks)),
    };
  });

  const gradedSubjects = subjects.filter((s) => s.marksObtained !== null);
  const total = gradedSubjects.reduce((sum, s) => sum + s.marksObtained, 0);
  const maxTotal = subjects.reduce((sum, s) => sum + s.maxMarks, 0);
  const overallPercentage = maxTotal > 0 ? Math.round((total / maxTotal) * 1000) / 10 : null;
  const overallGrade = overallPercentage === null ? null : gradeFor(overallPercentage);

  // Rank within the same tenant + exam_group cohort.
  const cohortTotals = await db
    .prepare(
      `SELECT m.student_id, SUM(m.marks_obtained) AS total
       FROM marks m
       JOIN assessments a ON a.id = m.assessment_id
       WHERE a.tenant_id = ? AND a.exam_group = ?
       GROUP BY m.student_id
       ORDER BY total DESC`
    )
    .all(tenantId, examGroup);
  const rank = cohortTotals.findIndex((r) => r.student_id === studentId) + 1;
  const cohortSize = cohortTotals.length;
  const batchAverage = cohortSize
    ? Math.round((cohortTotals.reduce((s, r) => s + Number(r.total), 0) / cohortSize) * 10) / 10
    : null;

  // Delta vs. the immediately previous exam_group this student also has
  // marks for, ordered by that exam_group's earliest assessment_date.
  const examGroupOrder = await db
    .prepare(
      `SELECT exam_group, MIN(assessment_date) AS first_date
       FROM assessments
       WHERE tenant_id = ? AND exam_group IS NOT NULL
       GROUP BY exam_group
       ORDER BY first_date ASC NULLS LAST`
    )
    .all(tenantId);
  const currentIdx = examGroupOrder.findIndex((g) => g.exam_group === examGroup);
  let previousDelta = null;
  for (let i = currentIdx - 1; i >= 0; i--) {
    const prevGroup = examGroupOrder[i].exam_group;
    const prevRow = await db
      .prepare(
        `SELECT SUM(m.marks_obtained) AS total, SUM(a.max_marks) AS max_total
         FROM assessments a
         LEFT JOIN marks m ON m.assessment_id = a.id AND m.student_id = ?
         WHERE a.tenant_id = ? AND a.exam_group = ?`
      )
      .get(studentId, tenantId, prevGroup);
    if (prevRow && prevRow.total !== null) {
      const prevPct = Math.round((Number(prevRow.total) / Number(prevRow.max_total)) * 1000) / 10;
      previousDelta = {
        comparedTo: prevGroup,
        previousPercentage: prevPct,
        change: Math.round((overallPercentage - prevPct) * 10) / 10,
      };
      break;
    }
  }

  return {
    examGroup,
    subjects,
    total,
    maxTotal,
    overallPercentage,
    overallGrade,
    rank,
    cohortSize,
    batchAverage,
    previousDelta,
  };
}

/// Every number the model states must appear (as a plain decimal string,
/// with the usual +/- rounding tolerance) in the computed summary it was
/// given — otherwise its answer is discarded in favour of a deterministic,
/// clearly-labelled fallback sentence. This is the same grounding check the
/// reference implementation used to stop a model's arithmetic mistake from
/// ever reaching a parent.
function extractNumbers(text) {
  return (text.match(/-?\d+(\.\d+)?/g) || []).map(Number);
}

function numbersAreGrounded(narrative, summary) {
  const allowed = new Set();
  const collect = (v) => {
    if (typeof v === 'number' && Number.isFinite(v)) allowed.add(Math.round(v * 10) / 10);
    else if (Array.isArray(v)) v.forEach(collect);
    else if (v && typeof v === 'object') Object.values(v).forEach(collect);
  };
  collect(summary);
  const stated = extractNumbers(narrative);
  return stated.every((n) => {
    const rounded = Math.round(n * 10) / 10;
    for (const a of allowed) {
      if (Math.abs(a - rounded) < 0.15) return true;
    }
    return false;
  });
}

function fallbackNarrative(summary, studentName) {
  const delta = summary.previousDelta
    ? `, ${summary.previousDelta.change >= 0 ? 'up' : 'down'} ${Math.abs(summary.previousDelta.change)} points from ${summary.previousDelta.comparedTo}`
    : '';
  return (
    `Computed summary for ${studentName}: ${summary.overallPercentage}% overall (grade ${summary.overallGrade}), ` +
    `rank ${summary.rank} of ${summary.cohortSize}${delta}. This is a computed summary, not an AI-written one.`
  );
}

async function generateNarrative(summary, studentName) {
  const prompt = `You are writing a short, warm 3-4 sentence note to a parent about their child's exam result.
Use ONLY the figures given below — do not calculate, estimate, or restate any number that is not listed here.

Student: ${studentName}
Overall: ${summary.overallPercentage}% (grade ${summary.overallGrade})
Rank: ${summary.rank} of ${summary.cohortSize}
Batch average: ${summary.batchAverage}/${summary.maxTotal}
${summary.previousDelta ? `Change since ${summary.previousDelta.comparedTo}: ${summary.previousDelta.change >= 0 ? '+' : ''}${summary.previousDelta.change} points` : ''}
Per-subject: ${summary.subjects.map((s) => `${s.subject} ${s.marksObtained ?? 'N/A'}/${s.maxMarks}`).join(', ')}

Write only the message text, no preamble.`;

  try {
    // 600, not 300 -- confirmed live this session that even with
    // thinkingBudget: 0, Gemini occasionally still spends a handful of
    // tokens on reasoning, and a tight budget makes that enough to cut the
    // visible narrative off mid-sentence (reproduced: "We are delighted to
    // share that SM" with narrativeIsFallback still false). More headroom
    // here than the risk-insight call's 400 since this prompt runs the
    // per-subject breakdown through too.
    const text = await generateText(prompt, { maxTokens: 600 });
    if (text && numbersAreGrounded(text, summary)) {
      return { narrative: text.trim(), isFallback: false };
    }
  } catch (err) {
    // Provider unavailable/failed — fall through to the deterministic summary.
  }
  return { narrative: fallbackNarrative(summary, studentName), isFallback: true };
}

/// Normalizes a guardian's phone where the pattern is unambiguous (a bare
/// 10-digit Indian/Nepali mobile); anything else is flagged `suspect`
/// rather than silently repaired, and sending should require a human to
/// have looked at it first.
function normalizeGuardianPhone(phone, countryCode) {
  const digits = digitsOnly(phone);
  if (!digits) return { number: null, suspect: true, reason: 'empty' };
  if (countryCode) {
    return { number: toWhatsAppNumber(phone, countryCode), suspect: false };
  }
  if (digits.length === 10) {
    return { number: toWhatsAppNumber(phone, '+91'), suspect: true, reason: 'country code assumed (+91), not stated' };
  }
  if (digits.length >= 11 && digits.length <= 13) {
    return { number: digits, suspect: false };
  }
  return { number: digits, suspect: true, reason: `unusual length (${digits.length} digits)` };
}

// ---------------------------------------------------------------------------
// Report templates — a real per-tenant customization point (which fields
// show, subject order, branding, footer/disclaimer), not a hardcoded
// layout. One sensible default is created for a tenant the first time it's
// needed (lazily, on first use) rather than requiring every tenant row to
// be seeded up front at migration time — a tenant created after this
// migration runs gets the same default automatically, with no extra step.
// ---------------------------------------------------------------------------

const DEFAULT_TEMPLATE_CONFIG = {
  fields: ['subjects', 'total', 'rank', 'batchAverage', 'previousDelta', 'narrative'],
  subjectOrder: null, // null = natural order (as returned by computeReportCard); or an explicit array of subject names
  branding: { headerColor: '#1e3a8a', title: null, logoUrl: null }, // null title -> student's own institution is used
  footerText: null,
  disclaimer: 'Marks are provisional until countersigned by the examination office.',
};

async function getOrCreateDefaultTemplate(tenantId) {
  let template = await db
    .prepare('SELECT * FROM report_templates WHERE tenant_id = ? AND is_default = true LIMIT 1')
    .get(tenantId);
  if (template) return template;

  template = await db
    .prepare(
      `INSERT INTO report_templates (id, tenant_id, name, config, is_default)
       VALUES (gen_random_uuid(), ?, 'Default', ?, true)
       RETURNING *`
    )
    .get(tenantId, JSON.stringify(DEFAULT_TEMPLATE_CONFIG));
  return template;
}

/// Guarded edit to an assessment. `max_marks`/`passing_marks` changes are
/// free ONLY when no mark has been recorded against this assessment yet;
/// once a mark exists, a change to either requires `confirmed: true` and a
/// `reason` (logged to assessment_revisions), and resets any not-yet-sent
/// ('ready') report_cards in that exam_group back to 'draft' so a stale
/// percentage already computed under the old max is never sent as-is.
/// Returns { updated: true } or { blocked: true, reason }.
async function updateAssessment(tenantId, assessmentId, changes, { confirmed, reason, revisedBy }) {
  const assessment = await db
    .prepare('SELECT * FROM assessments WHERE id = ? AND tenant_id = ?')
    .get(assessmentId, tenantId);
  if (!assessment) throw new Error('Assessment not found');

  const invalidatingFields = ['max_marks', 'passing_marks'];
  const touchesInvalidating = Object.keys(changes).some((k) => invalidatingFields.includes(k));

  let hasMarks = false;
  if (touchesInvalidating) {
    const markCount = await db.prepare('SELECT count(*) AS c FROM marks WHERE assessment_id = ?').get(assessmentId);
    hasMarks = Number(markCount.c) > 0;
  }

  if (hasMarks && touchesInvalidating && !confirmed) {
    return {
      blocked: true,
      reason: `${Object.keys(changes).filter((k) => invalidatingFields.includes(k)).join(', ')} already has recorded marks against it — pass confirmed: true and a reason to proceed anyway`,
    };
  }
  if (hasMarks && touchesInvalidating && !reason) {
    throw new Error('A reason is required when changing max_marks/passing_marks on an assessment with recorded marks');
  }

  await db.transaction(async (tx) => {
    if (hasMarks && touchesInvalidating) {
      for (const field of invalidatingFields) {
        if (field in changes && String(changes[field]) !== String(assessment[field])) {
          await tx
            .prepare(
              `INSERT INTO assessment_revisions (id, tenant_id, assessment_id, field_changed, previous_value, new_value, reason, revised_by)
               VALUES (gen_random_uuid(), ?, ?, ?, ?, ?, ?, ?)`
            )
            .run(tenantId, assessmentId, field, String(assessment[field]), String(changes[field]), reason, revisedBy);
        }
      }
      await tx
        .prepare(`UPDATE report_cards SET status = 'draft' WHERE tenant_id = ? AND exam_group = ? AND status = 'ready'`)
        .run(tenantId, assessment.exam_group);
    }

    const setClauses = Object.keys(changes).map((k) => `${k} = ?`).join(', ');
    await tx
      .prepare(`UPDATE assessments SET ${setClauses}, updated_at = now() WHERE id = ?`)
      .run(...Object.values(changes), assessmentId);
  });

  return { blocked: false, updated: true };
}

// ---------------------------------------------------------------------------
// Academic risk analysis (student-wise + batch-wise) — 2026-09-07.
//
// `subjects`/`assessments`/`marks`/`attendance_records`/`academic_risk_config`/
// `academic_risk_scores` were created back on 2026-08-15 for an earlier
// "Student Success & Academic Monitoring OS" effort that pivoted into a
// separate standalone product instead, leaving these tables live but
// completely unused. This revives the intent (a deterministic, explainable
// risk score first — never an AI guess — then one AI call to narrate it)
// against exam intelligence's real schema, mirroring the exact two-step
// pattern already proven by routes/scoring.js's /briefing endpoint and this
// file's own generateNarrative(): compute first, ask the model to describe
// the computed numbers, ground-or-fallback if it invents anything.
// ---------------------------------------------------------------------------

const DEFAULT_RISK_WEIGHTS = {
  criticalPercentage: 40, // latest exam % below this -> academic risk 'high'
  warningPercentage: 50, // latest exam % below this -> academic risk 'medium'
  decliningTrendPoints: 10, // a drop of this many points vs the previous exam also -> 'medium'
};

async function loadRiskConfig(tenantId) {
  const row = await db.prepare('SELECT * FROM academic_risk_config WHERE tenant_id = ?').get(tenantId);
  return {
    weights: { ...DEFAULT_RISK_WEIGHTS, ...(row?.weights || {}) },
    attendanceThresholdWarning: row?.attendance_threshold_warning ?? 75,
    attendanceThresholdCritical: row?.attendance_threshold_critical ?? 60,
  };
}

/// One row per exam_group this student has at least one recorded mark in,
/// oldest first. Deliberately lighter than computeReportCard (no rank/cohort/
/// narrative) -- this is a trend calculation across many exams, not a single
/// report render.
async function fetchStudentExamHistory(tenantId, studentId) {
  return db
    .prepare(
      `SELECT a.exam_group, SUM(m.marks_obtained) AS total, SUM(a.max_marks) AS max_total, MIN(a.assessment_date) AS first_date
       FROM assessments a
       JOIN marks m ON m.assessment_id = a.id AND m.student_id = ?
       WHERE a.tenant_id = ? AND a.exam_group IS NOT NULL
       GROUP BY a.exam_group
       ORDER BY first_date ASC NULLS LAST`
    )
    .all(studentId, tenantId);
}

async function fetchStudentAttendance(tenantId, studentId) {
  const rows = await db
    .prepare(`SELECT status, count(*) AS c FROM attendance_records WHERE tenant_id = ? AND student_id = ? GROUP BY status`)
    .all(tenantId, studentId);
  const total = rows.reduce((sum, r) => sum + Number(r.c), 0);
  if (!total) return null;
  const present = rows.filter((r) => r.status === 'present').reduce((sum, r) => sum + Number(r.c), 0);
  return { total, present, percentage: Math.round((present / total) * 1000) / 10 };
}

function riskBand(value, warningThreshold, criticalThreshold) {
  if (value < criticalThreshold) return 'high';
  if (value < warningThreshold) return 'medium';
  return 'low';
}

/// Deterministic first -- never guesses. Blocks with a clear reason (same
/// "ask, don't guess" philosophy as findMissingMaxSubjects) if this student
/// has no marks recorded anywhere yet.
async function computeStudentRisk(tenantId, studentId) {
  const history = await fetchStudentExamHistory(tenantId, studentId);
  if (!history.length) {
    return { blocked: true, reason: 'No marks recorded for this student yet' };
  }

  const config = await loadRiskConfig(tenantId);
  const percentages = history.map((h) => Math.round((Number(h.total) / Number(h.max_total)) * 1000) / 10);
  const latestExamGroup = history[history.length - 1].exam_group;
  const latestPercentage = percentages[percentages.length - 1];
  const trend = percentages.length >= 2 ? Math.round((percentages[percentages.length - 1] - percentages[percentages.length - 2]) * 10) / 10 : null;

  const decliningSharply = trend !== null && trend <= -config.weights.decliningTrendPoints;
  const academicRisk =
    latestPercentage < config.weights.criticalPercentage
      ? 'high'
      : latestPercentage < config.weights.warningPercentage || decliningSharply
        ? 'medium'
        : 'low';

  const attendance = await fetchStudentAttendance(tenantId, studentId);
  const attendanceRisk = attendance
    ? riskBand(attendance.percentage, config.attendanceThresholdWarning, config.attendanceThresholdCritical)
    : 'unknown';

  const RISK_RANK = { low: 0, medium: 1, high: 2, unknown: -1 };
  const overallRisk = RISK_RANK[attendanceRisk] > RISK_RANK[academicRisk] ? attendanceRisk : academicRisk;

  // Confidence grows with how much history backs the score -- 3+ exams is
  // treated as fully confident; fewer is honestly reported as less certain
  // rather than presenting a 1-exam snapshot with the same confidence as a
  // real trend.
  const confidence = Math.min(1, history.length / 3);

  const evidence = {
    examCount: history.length,
    latestExamGroup,
    latestPercentage,
    trend,
    attendancePercentage: attendance ? attendance.percentage : null,
    weightsUsed: config.weights,
  };

  return { blocked: false, academicRisk, attendanceRisk, overallRisk, confidence, evidence };
}

/// Persists a snapshot (one row per computation, not an upsert) so risk can
/// later be viewed as a history/trend of its own, not just a single
/// overwritten "current" value.
async function recordStudentRisk(tenantId, studentId, risk) {
  await db
    .prepare(
      `INSERT INTO academic_risk_scores (id, tenant_id, student_id, academic_risk, attendance_risk, overall_risk, confidence, evidence)
       VALUES (gen_random_uuid(), ?, ?, ?, ?, ?, ?, ?)`
    )
    .run(tenantId, studentId, risk.academicRisk, risk.attendanceRisk, risk.overallRisk, risk.confidence, JSON.stringify(risk.evidence));
}

function fallbackRiskInsight(studentName, risk) {
  const hasAttendance = risk.evidence.attendancePercentage !== null;
  return {
    insight:
      `Deterministic risk for ${studentName}: ${risk.overallRisk} overall, based on ${risk.evidence.examCount} exam(s)` +
      `${hasAttendance ? ' and attendance records' : ''}. Latest exam (${risk.evidence.latestExamGroup}): ${risk.evidence.latestPercentage}%` +
      `${risk.evidence.trend !== null ? `, ${risk.evidence.trend >= 0 ? '+' : ''}${risk.evidence.trend} points vs the previous exam` : ''}.`,
    recommendation:
      risk.overallRisk === 'high'
        ? 'Recommend a check-in with this student soon.'
        : risk.overallRisk === 'medium'
          ? 'Worth keeping an eye on this student\'s next exam.'
          : 'No urgent action needed based on current data.',
  };
}

/// Same grounding discipline as generateNarrative: one generateJson call,
/// strict "use only these numbers" prompt, deterministic fallback (never a
/// blank/broken insight) on any failure.
async function generateStudentRiskInsight(studentName, risk) {
  const e = risk.evidence;
  const prompt = `You are writing a short, factual academic risk insight for a counselor reviewing one student.
Use ONLY the figures given below — do not calculate, estimate, or restate any number that is not listed here.

Student: ${studentName}
Exams recorded: ${e.examCount}
Latest exam (${e.latestExamGroup}): ${e.latestPercentage}%
${e.trend !== null ? `Trend vs previous exam: ${e.trend >= 0 ? '+' : ''}${e.trend} points` : 'Trend: not enough exams yet to compute'}
Academic risk band: ${risk.academicRisk}
${e.attendancePercentage !== null ? `Attendance: ${e.attendancePercentage}%, band: ${risk.attendanceRisk}` : 'Attendance: no data recorded'}
Overall risk band: ${risk.overallRisk}

Respond ONLY with valid JSON, no other text, in exactly this shape:
{ "insight": "2-3 sentence factual observation about this student's trajectory, using only the numbers given", "recommendation": "one concrete suggested action for the counselor" }`;

  try {
    const result = await generateJson(prompt, { maxTokens: 400 });
    if (result && typeof result.insight === 'string' && typeof result.recommendation === 'string') {
      return { ...result, isFallback: false };
    }
  } catch (err) {
    // provider unavailable/failed -- fall through
  }
  return { ...fallbackRiskInsight(studentName, risk), isFallback: true };
}

/// Aggregates every student in one batch_year across all their exam groups.
/// No aggregation like this existed anywhere before this function.
/// `assignedTo`, when given, scopes to only students whose lead is assigned
/// to that user -- same owner/admin-see-all-else-see-own-caseload rule the
/// cohort endpoint already enforces.
async function computeBatchAnalysis(tenantId, batchYear, { assignedTo } = {}) {
  const students = assignedTo
    ? await db
        .prepare(
          `SELECT s.id, s.lead_id FROM students s JOIN leads l ON l.id = s.lead_id
           WHERE s.tenant_id = ? AND s.batch_year = ? AND l.tenant_id = ? AND l.assigned_to = ?`
        )
        .all(tenantId, batchYear, tenantId, assignedTo)
    : await db
        .prepare(`SELECT id, lead_id FROM students WHERE tenant_id = ? AND batch_year = ?`)
        .all(tenantId, batchYear);
  if (!students.length) {
    return { blocked: true, reason: `No students found for batch ${batchYear}` };
  }

  const perStudent = [];
  for (const s of students) {
    const risk = await computeStudentRisk(tenantId, s.id);
    if (!risk.blocked) perStudent.push(risk);
  }

  if (!perStudent.length) {
    return { blocked: true, reason: `No exam marks recorded yet for any student in batch ${batchYear}` };
  }

  const avgPercentage = Math.round((perStudent.reduce((sum, r) => sum + r.evidence.latestPercentage, 0) / perStudent.length) * 10) / 10;
  const riskCounts = { low: 0, medium: 0, high: 0 };
  perStudent.forEach((r) => { riskCounts[r.overallRisk] = (riskCounts[r.overallRisk] || 0) + 1; });

  return {
    blocked: false,
    batchYear,
    studentCount: students.length,
    analyzedCount: perStudent.length,
    averageLatestPercentage: avgPercentage,
    riskCounts,
  };
}

function fallbackBatchInsight(batch) {
  return {
    insight: `Batch ${batch.batchYear}: ${batch.analyzedCount} of ${batch.studentCount} students have recorded marks, averaging ${batch.averageLatestPercentage}% on their latest exam. Risk breakdown — high: ${batch.riskCounts.high}, medium: ${batch.riskCounts.medium}, low: ${batch.riskCounts.low}.`,
  };
}

async function generateBatchInsight(batch) {
  const prompt = `You are writing a short, factual summary for a college coordinator reviewing one batch's academic performance.
Use ONLY the figures given below.

Batch: ${batch.batchYear}
Students with marks recorded: ${batch.analyzedCount} of ${batch.studentCount}
Average latest-exam percentage: ${batch.averageLatestPercentage}%
Risk breakdown: ${batch.riskCounts.high} high, ${batch.riskCounts.medium} medium, ${batch.riskCounts.low} low

Respond ONLY with valid JSON, no other text, in exactly this shape:
{ "insight": "2-4 sentence factual summary of this batch's performance, using only the numbers given" }`;

  try {
    const result = await generateJson(prompt, { maxTokens: 400 });
    if (result && typeof result.insight === 'string') {
      return { insight: result.insight, isFallback: false };
    }
  } catch (err) {
    // provider unavailable/failed -- fall through
  }
  return { ...fallbackBatchInsight(batch), isFallback: true };
}

module.exports = {
  DEFAULT_TEMPLATE_CONFIG,
  getOrCreateDefaultTemplate,
  updateAssessment,
  parseMarksSheetBuffer,
  findMissingMaxSubjects,
  findOutOfRangeMarks,
  resolveStudents,
  importMarks,
  computeReportCard,
  gradeFor,
  generateNarrative,
  numbersAreGrounded,
  normalizeGuardianPhone,
  computeStudentRisk,
  recordStudentRisk,
  generateStudentRiskInsight,
  computeBatchAnalysis,
  generateBatchInsight,
};
