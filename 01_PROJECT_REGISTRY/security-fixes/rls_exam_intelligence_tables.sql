-- ============================================================================
-- TWO-TIER RLS — Exam Intelligence + Report Card tables
-- Project: leadflow-ai (Supabase ref: qovaakuithekhotkrrdi)
-- Drafted: 2026-09-06 — NOT YET APPLIED to the live database.
-- ============================================================================
--
-- Companion to `rls_54_tables_two_tier_lockdown.sql`. Covers the 4 new
-- tables added by `backend/migrations/2026-09-06-exam-intelligence-report-cards.js`
-- (also NOT YET APPLIED). Same policy model, same shared caveat about this
-- app's custom-JWT auth not reaching Supabase's `authenticated` role yet
-- (see that file's header) — restated here only for `report_templates`
-- since it's genuinely tenant-wide reference data like `assessments`/
-- `subjects` already are.
--
-- Apply this ONLY after: (1) the migration above has actually been run
-- against the live database (these tables don't exist yet), and (2) a
-- human has reviewed both files. Enable RLS + add each policy in the same
-- transaction per table, per the existing project convention (no gap
-- between enabling RLS and having a matching policy).

-- ----------------------------------------------------------------------------
-- D. report_templates — tenant-wide reference data, all roles.
--    Same shape as the existing tenant_wide_access_assessments /
--    tenant_wide_access_subjects policies.
-- ----------------------------------------------------------------------------
ALTER TABLE public.report_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_wide_access_report_templates
  ON public.report_templates
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- C2. report_cards — student_id -> students.lead_id -> leads.assigned_to
--     Identical join shape to two_tier_access_academic_risk_scores.
-- ----------------------------------------------------------------------------
ALTER TABLE public.report_cards ENABLE ROW LEVEL SECURITY;

CREATE POLICY two_tier_access_report_cards
  ON public.report_cards
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR EXISTS (
        SELECT 1
        FROM students s
        JOIN leads l ON l.id = s.lead_id
        WHERE s.id = report_cards.student_id
          AND s.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.assigned_to = (auth.jwt() ->> 'userId')
      )
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR EXISTS (
        SELECT 1
        FROM students s
        JOIN leads l ON l.id = s.lead_id
        WHERE s.id = report_cards.student_id
          AND s.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.assigned_to = (auth.jwt() ->> 'userId')
      )
    )
  );

-- ----------------------------------------------------------------------------
-- C2. mark_revisions — student_id -> students.lead_id -> leads.assigned_to
--     Same join shape again. `student_id` was denormalized onto this table
--     specifically so this policy doesn't need to join through marks/
--     assessments to reach a student.
-- ----------------------------------------------------------------------------
ALTER TABLE public.mark_revisions ENABLE ROW LEVEL SECURITY;

CREATE POLICY two_tier_access_mark_revisions
  ON public.mark_revisions
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR EXISTS (
        SELECT 1
        FROM students s
        JOIN leads l ON l.id = s.lead_id
        WHERE s.id = mark_revisions.student_id
          AND s.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.assigned_to = (auth.jwt() ->> 'userId')
      )
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR EXISTS (
        SELECT 1
        FROM students s
        JOIN leads l ON l.id = s.lead_id
        WHERE s.id = mark_revisions.student_id
          AND s.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.assigned_to = (auth.jwt() ->> 'userId')
      )
    )
  );

-- ----------------------------------------------------------------------------
-- D. assessment_revisions — tenant-wide, same shape as assessments itself.
-- ----------------------------------------------------------------------------
ALTER TABLE public.assessment_revisions ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_wide_access_assessment_revisions
  ON public.assessment_revisions
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- A. mark_imports — direct ownership via `recorded_by`.
--    Same shape as two_tier_access_marks.
-- ----------------------------------------------------------------------------
ALTER TABLE public.mark_imports ENABLE ROW LEVEL SECURITY;

CREATE POLICY two_tier_access_mark_imports
  ON public.mark_imports
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR recorded_by = (auth.jwt() ->> 'userId')
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR recorded_by = (auth.jwt() ->> 'userId')
    )
  );

-- ----------------------------------------------------------------------------
-- Verification block (run after applying, mirrors the 9-table/54-table
-- fixes' own verification style) — not executed by this file.
-- ----------------------------------------------------------------------------
-- SELECT tablename, rowsecurity FROM pg_tables
--   WHERE schemaname = 'public'
--   AND tablename IN ('report_templates','report_cards','mark_revisions','assessment_revisions','mark_imports');
-- SELECT tablename, policyname FROM pg_policies
--   WHERE schemaname = 'public'
--   AND tablename IN ('report_templates','report_cards','mark_revisions','assessment_revisions','mark_imports');
