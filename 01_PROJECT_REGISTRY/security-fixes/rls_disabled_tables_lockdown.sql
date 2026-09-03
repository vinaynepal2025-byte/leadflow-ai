-- ============================================================================
-- RLS LOCKDOWN — 9 tables with Row Level Security disabled entirely
-- Project: leadflow-ai (Supabase ref: qovaakuithekhotkrrdi)
-- Drafted: 2026-09-03 — NOT YET APPLIED to the live database.
-- ============================================================================
--
-- BACKGROUND / WHY THIS MIGRATION EXISTS
--
-- Live audit on 2026-09-03 (via supabase-primary MCP, read-only) confirmed:
--   - 0 rows in pg_policies across the entire `public` schema (no RLS policy
--     exists anywhere in this project, on any table).
--   - Of the project's 63 tables, 54 have RLS ENABLED with zero policies
--     (Postgres default-denies all access there for any non-bypassing role —
--     already effectively closed to anon/authenticated).
--   - The 9 tables listed below have RLS DISABLED ENTIRELY, and `anon` +
--     `authenticated` both hold full SELECT/INSERT/UPDATE/DELETE/TRUNCATE
--     grants on all 63 tables (Supabase's standard default PostgREST grant).
--     With RLS off, those grants are NOT gated by anything — anyone holding
--     this project's anon/publishable key can read, write, or delete rows in
--     these 9 tables directly via Supabase's auto-generated REST API,
--     completely bypassing the Node backend, its JWT auth, and every
--     tenant_id filter the route files apply.
--   - Confirmed live: `postgres` (the role backend/db.js connects as, via
--     PGUSER || 'postgres') has rolbypassrls = true. The backend's own
--     traffic never goes through RLS at all, on any table, today or after
--     this migration.
--
-- WHAT THIS MIGRATION DOES AND DOES NOT CHANGE
--
--   - It enables RLS and adds one tenant-scoped policy per table below.
--   - It does NOT change how the Node backend behaves. The backend connects
--     as `postgres`, which bypasses RLS unconditionally (confirmed above) —
--     every existing route, query, and route-level `WHERE tenant_id = ?`
--     clause keeps working exactly as it does today, unchanged.
--   - Its only real-world effect is closing the anon-key-direct-access gap
--     described above.
--
-- IMPORTANT CAVEAT — the `authenticated` policy's practical reach today
--
--   This app does not use Supabase Auth. `backend/routes/auth.js` signs its
--   own JWTs with a locally-configured `JWT_SECRET` (an app env var, not
--   Supabase's project JWT secret) and embeds a payload shape of
--   `{ userId, tenantId, role }` — a business `role` (e.g. "counselor"), not
--   the reserved Supabase/PostgREST `role: authenticated` claim, and a
--   `tenantId` claim (camelCase), not `tenant_id`.
--
--   Supabase/PostgREST only ever grants the `authenticated` role to a
--   request bearing a JWT it can verify with ITS OWN configured secret. This
--   app's tokens are signed with a different secret, so PostgREST will never
--   recognize them — no request produced by this app's own login flow can
--   currently present as `authenticated` to Supabase at all.
--
--   Net effect: today, the policies below are unreachable by ANY real
--   caller — anon is blocked because it matches no policy, and authenticated
--   is blocked because nothing this app issues can actually authenticate as
--   `authenticated` in Supabase's eyes. That fully closes the gap. The
--   policies are still written as real tenant-scoped rules (using the
--   `tenantId` claim shape this app already produces, via `auth.jwt()`)
--   rather than a blanket `USING (false)`, so the correct isolation model is
--   already encoded here for whenever/if this project adopts a Supabase-Auth
--   -compatible session (at which point this becomes real, active
--   protection instead of dormant defense-in-depth). Revisit this comment
--   before assuming these policies are "live" in the authenticated-user
--   sense.
--
-- SCHEMA VERIFIED LIVE BEFORE WRITING THIS FILE (not assumed):
--   - All 9 tables have a direct `tenant_id` column, type `text` (matches
--     `tenants.id`, also `text`).
--   - `tool_invocations.tenant_id` is NULLABLE (unlike the other 8, which are
--     NOT NULL) — see note on that table below.
--   - `dashboard_sections`, `lead_lifecycle_transitions`, `lead_list_fields`,
--     `tenant_assets`, `tenant_brand_kits` have tenant_id declared as an
--     actual FK to tenants(id).
--   - `automation_jobs`, `more_menu_items`, `nav_tabs`, `tool_invocations`
--     have NO foreign key constraint tying tenant_id to tenants(id) — a
--     pre-existing data-integrity gap, unrelated to RLS, NOT fixed by this
--     migration (flagged here for awareness only).
--
-- This migration enables RLS and adds its policy in the SAME statement block
-- per table (no gap between the two steps), per the audit's finding that a
-- table must never sit in an "RLS enabled, zero policies" state as a
-- separate step from "RLS enabled, policy live" — both happen together here.
--
-- THIS FILE HAS NOT BEEN APPLIED. Review before running against the live
-- project (qovaakuithekhotkrrdi) via mcp__supabase-primary__apply_migration
-- or the Supabase SQL editor.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. automation_jobs
--    tenant_id: text, NOT NULL, no FK to tenants(id) (see note above)
-- ----------------------------------------------------------------------------
ALTER TABLE public.automation_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_automation_jobs
  ON public.automation_jobs
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));


-- ----------------------------------------------------------------------------
-- 2. dashboard_sections
--    tenant_id: text, NOT NULL, FK -> tenants(id)
-- ----------------------------------------------------------------------------
ALTER TABLE public.dashboard_sections ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_dashboard_sections
  ON public.dashboard_sections
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));


-- ----------------------------------------------------------------------------
-- 3. lead_lifecycle_transitions
--    tenant_id: text, NOT NULL, FK -> tenants(id)
--    (also has lead_id -> leads(id), not needed for tenant scoping since
--    tenant_id is already a direct column on this table)
-- ----------------------------------------------------------------------------
ALTER TABLE public.lead_lifecycle_transitions ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_lead_lifecycle_transitions
  ON public.lead_lifecycle_transitions
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));


-- ----------------------------------------------------------------------------
-- 4. lead_list_fields
--    tenant_id: text, NOT NULL, FK -> tenants(id)
-- ----------------------------------------------------------------------------
ALTER TABLE public.lead_list_fields ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_lead_list_fields
  ON public.lead_list_fields
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));


-- ----------------------------------------------------------------------------
-- 5. more_menu_items
--    tenant_id: text, NOT NULL, no FK to tenants(id) (see note above)
-- ----------------------------------------------------------------------------
ALTER TABLE public.more_menu_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_more_menu_items
  ON public.more_menu_items
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));


-- ----------------------------------------------------------------------------
-- 6. nav_tabs
--    tenant_id: text, NOT NULL, no FK to tenants(id) (see note above)
-- ----------------------------------------------------------------------------
ALTER TABLE public.nav_tabs ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_nav_tabs
  ON public.nav_tabs
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));


-- ----------------------------------------------------------------------------
-- 7. tenant_assets
--    tenant_id: text, NOT NULL, FK -> tenants(id)
-- ----------------------------------------------------------------------------
ALTER TABLE public.tenant_assets ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_tenant_assets
  ON public.tenant_assets
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));


-- ----------------------------------------------------------------------------
-- 8. tenant_brand_kits
--    tenant_id: text, NOT NULL, FK -> tenants(id)
-- ----------------------------------------------------------------------------
ALTER TABLE public.tenant_brand_kits ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_tenant_brand_kits
  ON public.tenant_brand_kits
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));


-- ----------------------------------------------------------------------------
-- 9. tool_invocations
--    tenant_id: text, NULLABLE (unlike the other 8 tables), no FK to
--    tenants(id) (see note above).
--    Rows with tenant_id IS NULL are system/global tool-invocation log
--    entries (not tied to any tenant). Because the policy below requires an
--    exact tenant_id match, NULL-tenant rows will never satisfy it for the
--    `authenticated` role — they simply remain inaccessible via PostgREST,
--    same as every other row in this table. This is a safe default (no
--    accidental exposure of global rows); it does not affect the backend,
--    which reads/writes this table as `postgres` (bypasses RLS).
-- ----------------------------------------------------------------------------
ALTER TABLE public.tool_invocations ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_tool_invocations
  ON public.tool_invocations
  FOR ALL
  TO authenticated
  USING (tenant_id = (auth.jwt() ->> 'tenantId'))
  WITH CHECK (tenant_id = (auth.jwt() ->> 'tenantId'));


-- ============================================================================
-- END OF MIGRATION — 9 tables, 9 ENABLE + 9 CREATE POLICY statements.
-- Not applied. Nothing in this file has touched the live database.
-- ============================================================================
