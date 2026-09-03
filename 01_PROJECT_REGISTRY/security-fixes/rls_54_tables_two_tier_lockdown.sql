-- ============================================================================
-- TWO-TIER RLS LOCKDOWN — remaining 54 tables (RLS enabled, zero policies)
-- Project: leadflow-ai (Supabase ref: qovaakuithekhotkrrdi)
-- Drafted: 2026-09-03 — NOT YET APPLIED to the live database.
-- ============================================================================
--
-- BACKGROUND
--
-- Follows the 9-table fix in `rls_disabled_tables_lockdown.sql` (RLS was
-- fully disabled there; already applied and live-verified). These 54 tables
-- are a different starting state: RLS is already enabled, but zero policies
-- exist, so Postgres already default-denies `anon`/`authenticated` today.
-- This migration does not change that default-deny baseline for anyone
-- outside the two-tier model below — it only defines what `authenticated`
-- access should look like once/if this project ever issues sessions that
-- Supabase recognizes as `authenticated` (see the dormancy caveat below,
-- carried forward unchanged from the 9-table fix).
--
-- POLICY MODEL — per Vinay's decision
--
--   owner / admin  -> full tenant-wide access (all rows in their own tenant)
--   counselor / viewer / any other role -> only rows connected to them,
--     either directly (an ownership column on the table itself) or
--     transitively (via a join chain to a lead they are assigned_to)
--
-- Every table below falls into one of six buckets, each handled with its
-- own comment header:
--
--   0. tenants            -> NO POLICY AT ALL. Deny by default, backend-only
--                             (same treatment `postgres`'s BYPASSRLS already
--                             gives the app). Nothing to write here.
--   0b. users             -> NO POLICY on the base table (same as tenants).
--                             A `users_safe` view (password_hash excluded)
--                             carries the actual two-tier access logic.
--   A. Direct ownership column (17 tables) -> two-tier via that column.
--      (meetings was originally scoped here on `requested_by` but has been
--      moved to Group D below — that signal was judged too weak to rely on
--      for per-employee filtering; see Group D's note on it.)
--   B. Tenant-wide, all roles (2 tables: lead_notes, capture_forms) ->
--      no usable ownership column, so no per-employee split is possible.
--   C/C2. Lead-chain ownership (10 tables) -> two-tier via a join to
--      `leads.assigned_to`, 1-hop or 2-hop depending on the table.
--   D. Tenant-wide, all roles (21 tables, including `meetings` — moved from
--      Group A) -> genuinely tenant-level config/reference data, or in
--      `meetings`' case, a table whose only candidate ownership column
--      wasn't reliable enough to filter on.
--   Plus campaign_targets and alumni_availability (join-based, no direct
--      tenant_id column at all) -> two-tier via their own join chains.
--      alumni_availability keeps its originally-designed lead-chain scoping
--      (limited to the counselor assigned to the alum's own admission lead)
--      — the semantic-stretch flag noted below is a discussion point, not a
--      change made to the policy itself.
--
-- SHARED CAVEAT (unchanged from the 9-table fix, restated here because it
-- applies to every policy below)
--
--   This app does not use Supabase Auth. Its JWTs are signed with a local
--   `JWT_SECRET`, not Supabase's project JWT secret, so PostgREST never
--   recognizes them as `authenticated`. Every policy below is written as
--   real, correct two-tier logic (using the `tenantId` / `userId` / `role`
--   claim shape this app already produces) rather than a placeholder, so it
--   becomes active the moment a real Supabase-Auth-compatible session
--   exists — but today, nothing reaches the `authenticated` role at all.
--   The backend itself is entirely unaffected either way: it connects as
--   `postgres` (`rolbypassrls = true`, confirmed live), so none of this
--   changes existing app behavior.
--
-- NULLABLE OWNERSHIP COLUMNS (applies to every Group A / C / C2 table)
--
--   Every direct ownership column (assigned_to, created_by, recorded_by,
--   etc.) and every lead_id used in a join chain is nullable in the live
--   schema. A row whose ownership column is NULL, or whose lead_id is NULL,
--   will not match `<col> = (auth.jwt() ->> 'userId')` (NULL comparisons
--   are neither true nor false in SQL) — so unassigned/unlinked rows become
--   visible only to owner/admin, invisible to everyone else. This is a
--   deliberate, safe default (unassigned records default to admin-only
--   visibility, never leak to the wrong employee), not a bug — but it does
--   mean "employee sees own records" implicitly excludes anything not yet
--   assigned, for that employee.
--
-- OPEN QUESTIONS FLAGGED DURING PLANNING (not blocking — decisions already
-- made per your last message, restated here for the record)
--
--   - campaign_targets: two possible join paths existed (via campaign_id or
--     via lead_id). This migration uses lead_id -> leads, since ownership
--     naturally follows "whose lead is this a campaign target for," not
--     "who owns the campaign." Assumes campaign_id and lead_id on the same
--     campaign_targets row always belong to the same tenant — not enforced
--     by any DB constraint tying the two together.
--   - alumni_availability: this table describes an alumnus's own
--     availability/bio for mentoring, not a counselor's active caseload.
--     Scoping its visibility to "the counselor originally assigned to that
--     alum's admission lead" (the only join path available) is a semantic
--     stretch — alumni matching is often meant to work *across* leads, so a
--     different counselor recruiting a *new* lead may legitimately need to
--     see this alum's availability. Implemented as instructed below, but
--     flagged again here as worth a second look before applying.
--
-- THIS FILE HAS NOT BEEN APPLIED. Nothing in this file has touched the live
-- database. Review before running via mcp__supabase-primary__apply_migration.
-- ============================================================================


-- ============================================================================
-- 0. tenants — NO POLICY. Deny by default, backend-only.
-- ============================================================================
--
-- Deliberately no ALTER TABLE / CREATE POLICY statement here. `tenants`
-- already has RLS enabled with zero policies (confirmed live, unchanged
-- since the original audit) — that is already full default-deny for both
-- `anon` and `authenticated`, which is exactly the desired end state. The
-- only reader/writer of this table should ever be the backend's own
-- `postgres` connection (BYPASSRLS). Nothing to do; this section exists so
-- the omission reads as intentional, not forgotten.


-- ============================================================================
-- 0b. users — NO POLICY on the base table. users_safe view carries access.
-- ============================================================================
--
-- Same treatment as `tenants`: the base `users` table gets no authenticated
-- policy at all (it already has RLS enabled, zero policies — untouched by
-- this migration). password_hash must never be reachable via any
-- authenticated path, so rather than write a policy directly on `users`
-- (which Postgres RLS cannot column-filter — a policy governs which ROWS
-- are visible, not which columns), the two-tier access logic lives in a
-- view that excludes password_hash entirely.
--
-- Note on how this actually enforces anything: Postgres has no
-- "CREATE POLICY ON a view" — RLS policies attach only to tables. A plain
-- view (the default; NOT security_invoker) runs its underlying query as the
-- view's OWNER, not the querying session. Since this migration is applied
-- by a role with BYPASSRLS (postgres/service_role), the view "sees" every
-- row in `users` regardless of that table's own RLS state, and the WHERE
-- clause embedded in the view definition below is what actually implements
-- "owner/admin see all, everyone else sees only their own row" — it is
-- functionally the two-tier policy, just expressed as a view predicate
-- instead of a CREATE POLICY object. Do NOT add `WITH (security_invoker =
-- true)` to this view — that would make it inherit `users`' own (currently
-- policy-less, fully-denying) RLS instead of using this WHERE clause, and
-- the view would silently return zero rows for every authenticated caller.

CREATE VIEW public.users_safe
WITH (security_invoker = false) -- explicit, not just relying on the default — see note above
AS
SELECT
  id,
  tenant_id,
  email,
  full_name,
  role,
  created_at,
  active,
  invite_token,
  invite_token_expires_at
  -- password_hash intentionally excluded — this is the entire point of
  -- this view existing instead of exposing `users` directly.
FROM public.users
WHERE tenant_id = (auth.jwt() ->> 'tenantId')
  AND (
    (auth.jwt() ->> 'role') IN ('owner', 'admin')
    OR id = (auth.jwt() ->> 'userId')
  );

-- Read-only: this view is for profile lookups via PostgREST, not writes.
-- Team member creation/edit/delete already goes through the backend's own
-- `/auth/team` routes (`postgres` connection, admin-gated via
-- `requireRole('admin')`) — there's no reason for this view to be
-- updatable, and making it so would need its own WITH CHECK-equivalent
-- reasoning for INSERT/UPDATE, which is unnecessary scope for what this
-- view is for.
GRANT SELECT ON public.users_safe TO authenticated;
-- Deliberately no GRANT to `anon` — an unauthenticated caller has no
-- tenantId/userId claim to match against, so every row would evaluate to
-- NULL/false anyway, but there's no reason to grant table-level SELECT
-- privilege to a role that can never legitimately use it.


-- ============================================================================
-- GROUP A — 18 tables with a direct ownership/assignment column
-- Pattern: owner/admin see all tenant rows; everyone else sees only rows
-- where the ownership column matches their own userId.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A1. leads — assigned_to
--     The core table: every Group C/C2 policy below ultimately traces back
--     to this table's assigned_to column.
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_leads
  ON public.leads
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR assigned_to = (auth.jwt() ->> 'userId')
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR assigned_to = (auth.jwt() ->> 'userId')
    )
  );

-- ----------------------------------------------------------------------------
-- A2. tasks — assigned_to
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_tasks
  ON public.tasks
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR assigned_to = (auth.jwt() ->> 'userId')
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR assigned_to = (auth.jwt() ->> 'userId')
    )
  );

-- ----------------------------------------------------------------------------
-- A3. reminders — assigned_to
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_reminders
  ON public.reminders
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR assigned_to = (auth.jwt() ->> 'userId')
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR assigned_to = (auth.jwt() ->> 'userId')
    )
  );

-- ----------------------------------------------------------------------------
-- A4. documents — uploaded_by
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_documents
  ON public.documents
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR uploaded_by = (auth.jwt() ->> 'userId')
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR uploaded_by = (auth.jwt() ->> 'userId')
    )
  );

-- ----------------------------------------------------------------------------
-- A5. communications — created_by
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_communications
  ON public.communications
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR created_by = (auth.jwt() ->> 'userId')
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR created_by = (auth.jwt() ->> 'userId')
    )
  );

-- ----------------------------------------------------------------------------
-- A6. voice_notes — recorded_by
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_voice_notes
  ON public.voice_notes
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
-- A7. call_logs — called_by
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_call_logs
  ON public.call_logs
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR called_by = (auth.jwt() ->> 'userId')
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR called_by = (auth.jwt() ->> 'userId')
    )
  );

-- ----------------------------------------------------------------------------
-- A8. consent_records — recorded_by
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_consent_records
  ON public.consent_records
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
-- A9. content_sends — sent_by
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_content_sends
  ON public.content_sends
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR sent_by = (auth.jwt() ->> 'userId')
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR sent_by = (auth.jwt() ->> 'userId')
    )
  );

-- ----------------------------------------------------------------------------
-- A10. data_requests — handled_by
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_data_requests
  ON public.data_requests
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR handled_by = (auth.jwt() ->> 'userId')
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR handled_by = (auth.jwt() ->> 'userId')
    )
  );

-- ----------------------------------------------------------------------------
-- A11. flyer_projects — created_by
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_flyer_projects
  ON public.flyer_projects
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR created_by = (auth.jwt() ->> 'userId')
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR created_by = (auth.jwt() ->> 'userId')
    )
  );

-- ----------------------------------------------------------------------------
-- A12. marks — recorded_by
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_marks
  ON public.marks
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
-- A13. offers — given_by
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_offers
  ON public.offers
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR given_by = (auth.jwt() ->> 'userId')
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR given_by = (auth.jwt() ->> 'userId')
    )
  );

-- ----------------------------------------------------------------------------
-- A14. scheduled_messages — created_by
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_scheduled_messages
  ON public.scheduled_messages
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR created_by = (auth.jwt() ->> 'userId')
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR created_by = (auth.jwt() ->> 'userId')
    )
  );

-- ----------------------------------------------------------------------------
-- A15. student_checkins — conducted_by
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_student_checkins
  ON public.student_checkins
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR conducted_by = (auth.jwt() ->> 'userId')
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR conducted_by = (auth.jwt() ->> 'userId')
    )
  );

-- ----------------------------------------------------------------------------
-- A16. attendance_records — recorded_by
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_attendance_records
  ON public.attendance_records
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
-- A17. notifications — user_id
--      Different semantics from the rest of this group: user_id identifies
--      who the notification is FOR (its recipient), not who created it.
--      "Ownership" here correctly means "mine to see" either way, so the
--      same pattern applies unchanged.
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_notifications
  ON public.notifications
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR user_id = (auth.jwt() ->> 'userId')
    )
  )
  WITH CHECK (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR user_id = (auth.jwt() ->> 'userId')
    )
  );

-- (A18 was originally meetings:requested_by here — moved to Group D below
-- per Vinay's decision that requested_by is too weak/inconsistently
-- populated a signal to filter per-employee access on. See Group D.)

-- ============================================================================
-- GROUP B — 2 tables, no usable ownership column, tenant-wide for all roles
-- Pattern: tenant_id match only, every authenticated role in the tenant gets
-- full read/write.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- B1. lead_notes
--     Has `author_name`, but that's a free-text label, not a user_id FK —
--     cannot be reliably matched against auth.jwt()->>'userId'.
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_lead_notes
  ON public.lead_notes
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- B2. capture_forms
--     Has `assign_to`, but that's a config value (who NEW leads captured
--     through this form get assigned to), not an ownership marker for the
--     capture_forms record itself.
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_capture_forms
  ON public.capture_forms
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));


-- ============================================================================
-- GROUP C — 8 tables, no ownership column, but a direct lead_id to join
-- through to leads.assigned_to (1 hop).
-- Pattern: owner/admin see all tenant rows; everyone else sees only rows
-- whose lead_id points to a lead assigned to them.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- C1. admission_applications — lead_id -> leads.assigned_to
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_admission_applications
  ON public.admission_applications
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR EXISTS (
        SELECT 1 FROM public.leads l
        WHERE l.id = admission_applications.lead_id
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
        SELECT 1 FROM public.leads l
        WHERE l.id = admission_applications.lead_id
          AND l.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.assigned_to = (auth.jwt() ->> 'userId')
      )
    )
  );

-- ----------------------------------------------------------------------------
-- C2. alumni_connections — lead_id -> leads.assigned_to
--     (also has student_id, not used here — lead_id is the more direct
--     ownership signal, matching who is currently working this lead)
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_alumni_connections
  ON public.alumni_connections
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR EXISTS (
        SELECT 1 FROM public.leads l
        WHERE l.id = alumni_connections.lead_id
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
        SELECT 1 FROM public.leads l
        WHERE l.id = alumni_connections.lead_id
          AND l.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.assigned_to = (auth.jwt() ->> 'userId')
      )
    )
  );

-- ----------------------------------------------------------------------------
-- C3. fee_payments — lead_id -> leads.assigned_to
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_fee_payments
  ON public.fee_payments
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR EXISTS (
        SELECT 1 FROM public.leads l
        WHERE l.id = fee_payments.lead_id
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
        SELECT 1 FROM public.leads l
        WHERE l.id = fee_payments.lead_id
          AND l.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.assigned_to = (auth.jwt() ->> 'userId')
      )
    )
  );

-- ----------------------------------------------------------------------------
-- C4. flyers — lead_id -> leads.assigned_to
--     lead_id is NULLABLE here (unlike the others in this group) — some
--     flyers are general-purpose, not tied to a specific lead. A NULL
--     lead_id means the EXISTS subquery can never match, so non-admin roles
--     will not see or write general (non-lead) flyers under this policy —
--     only owner/admin will. Flag this if counselors are expected to create
--     their own general marketing flyers independent of a lead.
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_flyers
  ON public.flyers
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR EXISTS (
        SELECT 1 FROM public.leads l
        WHERE l.id = flyers.lead_id
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
        SELECT 1 FROM public.leads l
        WHERE l.id = flyers.lead_id
          AND l.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.assigned_to = (auth.jwt() ->> 'userId')
      )
    )
  );

-- ----------------------------------------------------------------------------
-- C5. peer_review_bookings — lead_id -> leads.assigned_to
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_peer_review_bookings
  ON public.peer_review_bookings
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR EXISTS (
        SELECT 1 FROM public.leads l
        WHERE l.id = peer_review_bookings.lead_id
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
        SELECT 1 FROM public.leads l
        WHERE l.id = peer_review_bookings.lead_id
          AND l.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.assigned_to = (auth.jwt() ->> 'userId')
      )
    )
  );

-- ----------------------------------------------------------------------------
-- C6. students — lead_id -> leads.assigned_to
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_students
  ON public.students
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR EXISTS (
        SELECT 1 FROM public.leads l
        WHERE l.id = students.lead_id
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
        SELECT 1 FROM public.leads l
        WHERE l.id = students.lead_id
          AND l.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.assigned_to = (auth.jwt() ->> 'userId')
      )
    )
  );

-- ----------------------------------------------------------------------------
-- C7. travel_plans — lead_id -> leads.assigned_to
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_travel_plans
  ON public.travel_plans
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR EXISTS (
        SELECT 1 FROM public.leads l
        WHERE l.id = travel_plans.lead_id
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
        SELECT 1 FROM public.leads l
        WHERE l.id = travel_plans.lead_id
          AND l.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.assigned_to = (auth.jwt() ->> 'userId')
      )
    )
  );

-- ----------------------------------------------------------------------------
-- C8. visa_applications — lead_id -> leads.assigned_to
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_visa_applications
  ON public.visa_applications
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR EXISTS (
        SELECT 1 FROM public.leads l
        WHERE l.id = visa_applications.lead_id
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
        SELECT 1 FROM public.leads l
        WHERE l.id = visa_applications.lead_id
          AND l.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.assigned_to = (auth.jwt() ->> 'userId')
      )
    )
  );


-- ============================================================================
-- GROUP C2 — 2 tables, no ownership column, no direct lead_id either —
-- 2-hop join required to reach leads.assigned_to.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- C2-1. academic_risk_scores — student_id -> students.lead_id -> leads.assigned_to
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_academic_risk_scores
  ON public.academic_risk_scores
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR EXISTS (
        SELECT 1
        FROM public.students s
        JOIN public.leads l ON l.id = s.lead_id
        WHERE s.id = academic_risk_scores.student_id
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
        FROM public.students s
        JOIN public.leads l ON l.id = s.lead_id
        WHERE s.id = academic_risk_scores.student_id
          AND s.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.assigned_to = (auth.jwt() ->> 'userId')
      )
    )
  );

-- ----------------------------------------------------------------------------
-- C2-2. payment_links — fee_payment_id -> fee_payments.lead_id -> leads.assigned_to
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_payment_links
  ON public.payment_links
  FOR ALL
  TO authenticated
  USING (
    tenant_id = (auth.jwt() ->> 'tenantId')
    AND (
      (auth.jwt() ->> 'role') IN ('owner', 'admin')
      OR EXISTS (
        SELECT 1
        FROM public.fee_payments fp
        JOIN public.leads l ON l.id = fp.lead_id
        WHERE fp.id = payment_links.fee_payment_id
          AND fp.tenant_id = (auth.jwt() ->> 'tenantId')
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
        FROM public.fee_payments fp
        JOIN public.leads l ON l.id = fp.lead_id
        WHERE fp.id = payment_links.fee_payment_id
          AND fp.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.tenant_id = (auth.jwt() ->> 'tenantId')
          AND l.assigned_to = (auth.jwt() ->> 'userId')
      )
    )
  );


-- ============================================================================
-- GROUP D — 21 tables, tenant-wide for all authenticated roles
-- Pattern: tenant_id match only. Genuinely tenant-level config/reference
-- data (pipeline stage names, custom field definitions, templates, the
-- college directory, etc.) that every employee in the tenant needs to read,
-- not per-employee data — plus `meetings`, moved here from Group A.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- D1. meetings
--     Moved from Group A: its only candidate ownership column
--     (requested_by) was judged too weak/inconsistently populated to filter
--     per-employee access on. Defaults to tenant-wide for all roles instead
--     of risking hiding real meetings from the counselor who should see
--     them. Revisit if a reliable owner column is added later (e.g. a
--     dedicated `assigned_to` on this table).
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_meetings
  ON public.meetings
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D2. academic_risk_config
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_academic_risk_config
  ON public.academic_risk_config
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D3. assessments
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_assessments
  ON public.assessments
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D4. automation_rules
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_automation_rules
  ON public.automation_rules
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D5. campaigns
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_campaigns
  ON public.campaigns
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D6. colleges
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_colleges
  ON public.colleges
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D7. consent_form_templates
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_consent_form_templates
  ON public.consent_form_templates
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D8. content_library
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_content_library
  ON public.content_library
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D9. custom_field_definitions
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_custom_field_definitions
  ON public.custom_field_definitions
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D10. knowledge_articles
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_knowledge_articles
  ON public.knowledge_articles
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D11. lead_detail_sections
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_lead_detail_sections
  ON public.lead_detail_sections
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D12. link_clicks
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_link_clicks
  ON public.link_clicks
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D13. pipeline_stages
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_pipeline_stages
  ON public.pipeline_stages
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D14. review_providers
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_review_providers
  ON public.review_providers
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D15. scoring_config
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_scoring_config
  ON public.scoring_config
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D16. share_targets
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_share_targets
  ON public.share_targets
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D17. subjects
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_subjects
  ON public.subjects
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D18. tenant_logos
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_tenant_logos
  ON public.tenant_logos
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D19. tracked_links
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_tracked_links
  ON public.tracked_links
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D20. visa_checklist_items
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_visa_checklist_items
  ON public.visa_checklist_items
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));

-- ----------------------------------------------------------------------------
-- D21. whatsapp_templates
-- ----------------------------------------------------------------------------
CREATE POLICY tenant_wide_access_whatsapp_templates
  ON public.whatsapp_templates
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));


-- ============================================================================
-- JOIN-BASED TABLES — no direct tenant_id column at all
-- ============================================================================

-- ----------------------------------------------------------------------------
-- campaign_targets — no tenant_id column. Joins via lead_id -> leads (chosen
-- over campaign_id -> campaigns; see header note on this choice and its
-- assumption that lead_id and campaign_id always agree on tenant).
-- Ownership: the lead's assigned_to, since visibility naturally follows
-- "whose lead is this a campaign target for."
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_campaign_targets
  ON public.campaign_targets
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.leads l
      WHERE l.id = campaign_targets.lead_id
        AND l.tenant_id = (auth.jwt() ->> 'tenantId')
        AND (
          (auth.jwt() ->> 'role') IN ('owner', 'admin')
          OR l.assigned_to = (auth.jwt() ->> 'userId')
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.leads l
      WHERE l.id = campaign_targets.lead_id
        AND l.tenant_id = (auth.jwt() ->> 'tenantId')
        AND (
          (auth.jwt() ->> 'role') IN ('owner', 'admin')
          OR l.assigned_to = (auth.jwt() ->> 'userId')
        )
    )
  );

-- ----------------------------------------------------------------------------
-- alumni_availability — no tenant_id column. Joins via
-- student_id -> students.lead_id -> leads (2-hop, same chain as
-- academic_risk_scores above). Kept as originally designed per Vinay's
-- instruction — see header note flagging this as a semantic stretch worth a
-- second look (alumni matching often needs to work across leads, not just
-- for the counselor who originally worked the alum's own admission), but
-- the policy itself is unchanged from the original plan.
-- ----------------------------------------------------------------------------
CREATE POLICY two_tier_access_alumni_availability
  ON public.alumni_availability
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.students s
      JOIN public.leads l ON l.id = s.lead_id
      WHERE s.id = alumni_availability.student_id
        AND s.tenant_id = (auth.jwt() ->> 'tenantId')
        AND l.tenant_id = (auth.jwt() ->> 'tenantId')
        AND (
          (auth.jwt() ->> 'role') IN ('owner', 'admin')
          OR l.assigned_to = (auth.jwt() ->> 'userId')
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.students s
      JOIN public.leads l ON l.id = s.lead_id
      WHERE s.id = alumni_availability.student_id
        AND s.tenant_id = (auth.jwt() ->> 'tenantId')
        AND l.tenant_id = (auth.jwt() ->> 'tenantId')
        AND (
          (auth.jwt() ->> 'role') IN ('owner', 'admin')
          OR l.assigned_to = (auth.jwt() ->> 'userId')
        )
    )
  );


-- ============================================================================
-- END OF MIGRATION.
-- Tables covered: tenants (no policy, intentional), users (no policy on
-- base table) + users_safe view, Group A (17), Group B (2), Group C (8),
-- Group C2 (2), Group D (21), campaign_targets, alumni_availability.
-- 17 + 2 + 8 + 2 + 21 + 2 = 52 tables with a CREATE POLICY, + tenants/users
-- handled without one = 54 tables total addressed, matching the full
-- remaining-tables scope.
-- Not applied. Nothing in this file has touched the live database.
-- ============================================================================
