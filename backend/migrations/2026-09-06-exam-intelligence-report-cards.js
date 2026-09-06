// Migration: 2026-09-06 — Exam Intelligence + Report Card System
// Idempotent, matches the established migration pattern (see
// 2026-09-03-lead-remarks-and-alternate-contact.js).
// Run with: node migrations/2026-09-06-exam-intelligence-report-cards.js
//
// NOT YET APPLIED. Draft only — every table/column referenced below was
// confirmed live via the supabase-primary MCP connection before writing
// this file (qovaakuithekhotkrrdi), nothing assumed.
//
// CONTEXT: leadflow-ai already had `students`, `subjects`, `assessments`,
// `marks`, `attendance_records`, `academic_risk_scores`/`_config` sitting
// unused (0 rows, no routes). This migration adds only what those tables
// don't already cover: (1) a way to group several subjects' `assessments`
// into one named exam sitting for report-card purposes, (2) the report
// card itself, (3) an audit trail for corrected marks, (4) a log of
// spreadsheet import attempts. It deliberately does NOT add a `guardians`
// table — `leads.parent_name` / `leads.parent_phone` / `leads.parent_relation`
// (confirmed live) already cover that via `students.lead_id`.

require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.PGHOST,
  port: process.env.PGPORT,
  user: process.env.PGUSER,
  password: process.env.PGPASSWORD,
  database: process.env.PGDATABASE,
  ssl: { rejectUnauthorized: false },
});

// --- assessments: exam_group ------------------------------------------------
//
// `assessments` is per-subject (one row = one subject's paper). A report
// card covers one *sitting* across several subjects at once (e.g. "MBBS 1st
// Year 2nd Internal Assessment"). Rather than inventing a parallel `exams`
// table, one nullable TEXT grouping key lets several existing `assessments`
// rows (same tenant, same subjects' batch) be treated as one named exam for
// report-card purposes — additive, no existing row or route is affected
// since the column defaults to NULL and nothing currently reads it.
const assessmentsExamGroup = [
  `ALTER TABLE assessments ADD COLUMN IF NOT EXISTS exam_group TEXT`,
  `CREATE INDEX IF NOT EXISTS idx_assessments_exam_group ON assessments (tenant_id, exam_group) WHERE exam_group IS NOT NULL`,
];

// --- report_templates (Group D: tenant-wide reference data, like
//     `assessments`/`subjects` already are in the two-tier RLS model) -------
const reportTemplates = [
  `CREATE TABLE IF NOT EXISTS report_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id TEXT NOT NULL,
    name TEXT NOT NULL,
    config JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_default BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )`,
  `CREATE INDEX IF NOT EXISTS idx_report_templates_tenant ON report_templates (tenant_id)`,
];

// --- report_cards (Group C2: student_id -> students.lead_id ->
//     leads.assigned_to, same shape as the existing academic_risk_scores
//     policy) -------------------------------------------------------------
//
// `computed_summary` holds every figure the card shows (per-subject marks,
// max, percentage, grade, total, overall percentage, rank, previous-exam
// delta) computed in services/examIntelligence.js from `marks`/`assessments`
// — never written by the AI model. `ai_narrative` is the model's prose
// about those figures; `ai_narrative_is_fallback` is true when no provider
// key was available or every provider failed and a deterministic
// computed-not-written summary was substituted instead (mirrors the
// reference implementation's fallback discipline).
const reportCards = [
  `CREATE TABLE IF NOT EXISTS report_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id TEXT NOT NULL,
    student_id TEXT NOT NULL REFERENCES students(id),
    exam_group TEXT NOT NULL,
    template_id UUID REFERENCES report_templates(id),
    computed_summary JSONB NOT NULL,
    ai_narrative TEXT,
    ai_narrative_is_fallback BOOLEAN NOT NULL DEFAULT false,
    image_storage_path TEXT,
    status TEXT NOT NULL DEFAULT 'draft',
    generated_at TIMESTAMPTZ,
    generated_by TEXT,
    sent_at TIMESTAMPTZ,
    sent_to_phone TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (student_id, exam_group)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_report_cards_tenant ON report_cards (tenant_id)`,
  `CREATE INDEX IF NOT EXISTS idx_report_cards_student ON report_cards (student_id)`,
  `CREATE INDEX IF NOT EXISTS idx_report_cards_exam_group ON report_cards (tenant_id, exam_group)`,
];

// --- mark_revisions (Group C2: student_id -> students.lead_id ->
//     leads.assigned_to) — a corrected mark is a logged conflict, never a
//     silent overwrite. `student_id` is denormalized onto this table
//     (rather than requiring a join through marks -> assessments) purely so
//     its RLS policy can match academic_risk_scores' join shape directly. --
const markRevisions = [
  `CREATE TABLE IF NOT EXISTS mark_revisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id TEXT NOT NULL,
    mark_id UUID NOT NULL REFERENCES marks(id),
    student_id TEXT NOT NULL REFERENCES students(id),
    previous_value NUMERIC,
    new_value NUMERIC NOT NULL,
    reason TEXT NOT NULL,
    revised_by TEXT NOT NULL,
    revised_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )`,
  `CREATE INDEX IF NOT EXISTS idx_mark_revisions_tenant ON mark_revisions (tenant_id)`,
  `CREATE INDEX IF NOT EXISTS idx_mark_revisions_student ON mark_revisions (student_id)`,
  `CREATE INDEX IF NOT EXISTS idx_mark_revisions_mark ON mark_revisions (mark_id)`,
];

// --- assessment_revisions (Group D: tenant-wide, same as `assessments`
//     itself) — logs a guarded edit to an assessment's max_marks/
//     passing_marks (or any other field judged to invalidate marks already
//     recorded against it). A subject's *name* is a label and is edited
//     directly on `subjects` with no revision log; changing what a mark
//     already recorded against an assessment actually means (its max) is
//     the case this table exists for — see routes/exams.js's guard: this
//     requires `confirmed: true` + a reason only when marks already exist
//     for that assessment, and resets any not-yet-sent report_cards in
//     that exam_group back to 'draft' so a stale percentage is never sent.
const assessmentRevisions = [
  `CREATE TABLE IF NOT EXISTS assessment_revisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id TEXT NOT NULL,
    assessment_id UUID NOT NULL REFERENCES assessments(id),
    field_changed TEXT NOT NULL,
    previous_value TEXT,
    new_value TEXT NOT NULL,
    reason TEXT NOT NULL,
    revised_by TEXT NOT NULL,
    revised_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )`,
  `CREATE INDEX IF NOT EXISTS idx_assessment_revisions_tenant ON assessment_revisions (tenant_id)`,
  `CREATE INDEX IF NOT EXISTS idx_assessment_revisions_assessment ON assessment_revisions (assessment_id)`,
];

// --- mark_imports (Group A: direct ownership via `recorded_by`, same shape
//     as the existing `marks` policy) — an operational log, not per-student
//     data, so it does not need the student-chain join. --------------------
const markImports = [
  `CREATE TABLE IF NOT EXISTS mark_imports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id TEXT NOT NULL,
    exam_group TEXT,
    file_name TEXT,
    mode TEXT NOT NULL DEFAULT 'strict',
    status TEXT NOT NULL DEFAULT 'pending',
    total_rows INTEGER,
    imported_rows INTEGER,
    blocked_reason TEXT,
    blocked_details JSONB,
    recorded_by TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )`,
  `CREATE INDEX IF NOT EXISTS idx_mark_imports_tenant ON mark_imports (tenant_id)`,
];

const statements = [
  ...assessmentsExamGroup,
  ...reportTemplates,
  ...reportCards,
  ...markRevisions,
  ...assessmentRevisions,
  ...markImports,
];

(async () => {
  for (const sql of statements) {
    console.log('Running:', sql.slice(0, 80).replace(/\s+/g, ' '), '...');
    await pool.query(sql);
  }
  console.log('Done.');
  await pool.end();
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
