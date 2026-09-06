# IMPLEMENTATION_PROGRESS.md — LeadFlow AI

Tracks real, verified changes made against the Master Spec's phased roadmap
(`IMPLEMENTATION_PLAN.md`) and the issues catalogued in `TECH_DEBT.md`. Only
entries that were actually applied and verified live belong here — see
`DECISION_LOG.md` for the reasoning behind why a given fix was prioritized.

---

## 2026-09-03 — RLS lockdown: 9 tables with Row Level Security disabled

**Phase context:** ahead of `IMPLEMENTATION_PLAN.md` Phase 1b (schema
hardening) — a live audit surfaced this as a standalone, urgent security gap
worth fixing on its own rather than waiting for the full Phase 1b pass.

**What was wrong:** a live re-audit of the `leadflow-ai` Supabase project
(`qovaakuithekhotkrrdi`, via the `supabase-primary` MCP, read-only) found the
schema had grown to 63 tables, and split `TECH_DEBT.md`'s existing RLS
finding into two buckets: 54 tables with RLS enabled but zero policies
(already effectively default-deny for `anon`/`authenticated`), and **9
tables with RLS disabled entirely** — `automation_jobs`, `dashboard_sections`,
`lead_lifecycle_transitions`, `lead_list_fields`, `more_menu_items`,
`nav_tabs`, `tenant_assets`, `tenant_brand_kits`, `tool_invocations`. Because
Supabase grants `anon`/`authenticated` full CRUD on every table by default,
these 9 were reachable for direct read/write/delete by anyone holding the
project's anon key via PostgREST — bypassing the Node backend, its JWT auth,
and every route-level `tenant_id` filter entirely.

**What was done:**
1. Verified the actual live schema for all 9 tables (columns, types,
   nullability, foreign keys) via `supabase-primary` before drafting anything
   — no structure was assumed.
2. Drafted `01_PROJECT_REGISTRY/security-fixes/rls_disabled_tables_lockdown.sql`:
   for each table, `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` and
   `CREATE POLICY ... FOR ALL TO authenticated USING/WITH CHECK (tenant_id =
   (auth.jwt() ->> 'tenantId'))` in the same migration block (no gap between
   enabling RLS and adding its policy).
3. Applied live via `mcp__supabase-primary__apply_migration` against
   `qovaakuithekhotkrrdi` (an active, non-paused project — no restore
   needed).
4. Verified live, 9/9 PASS: `rls_enabled = true` and exactly one policy on
   each of the 9 tables (via `pg_policies`/`pg_class`); confirmed
   `postgres`/`service_role` still show `rolbypassrls = true` afterward
   (unaffected); confirmed the backend's bypass-privileged connection can
   still read real data from all 9 tables (row counts matched expectations,
   e.g. `automation_jobs`: 3,461 rows) — no data modified, no test rows
   inserted.

**What this did and did not change:**
- Closed: direct anon-key access to these 9 tables via PostgREST.
- Unchanged: the Node backend's behavior. It connects as `postgres`
  (`rolbypassrls = true`), so every existing route and query works exactly
  as before.
- Caveat: the `authenticated`-role policy is dormant defense-in-depth today,
  not active per-user filtering. This app doesn't use Supabase Auth — its
  JWTs are signed with a local `JWT_SECRET` and carry a `tenantId` claim,
  never recognized by Supabase as `authenticated`. In practice this means
  both `anon` and `authenticated` PostgREST access are now fully denied on
  these 9 tables, which is the intended outcome, but the policy would only
  become *active* per-tenant filtering if this project ever adopts a
  Supabase-Auth-compatible session.

**Still open (not addressed by this fix):** the 54 RLS-enabled-zero-policy
tables (including all core CRM tables — `leads`, `users`, `communications`,
etc.) still need a real tenant-scoping policy design. See `TECH_DEBT.md` §2
and `DECISION_LOG.md` for why this was sequenced after the 9-table fix.

**Verification status: PASS** — live-verified, not inferred from docs.

---

## 2026-09-03 — Two-tier RLS lockdown: remaining 54 tables (RLS enabled, zero policies)

**Phase context:** direct follow-up to the 9-table fix above, same day — closes the "still open" item that entry flagged.

**What was wrong:** the 54 tables left over after the 9-table fix already had RLS enabled with zero policies, which meant `anon`/`authenticated` were already default-denied there — not an active exposure, but also no real access model existed for the day this project needs one (e.g. if it ever adopts Supabase-Auth-compatible sessions, or for any future direct-PostgREST client).

**What was done:**
1. Audited all 51 direct-`tenant_id` tables (of the 54) for an ownership/assignment column (`assigned_to`, `created_by`, `recorded_by`, etc.), and separately mapped join chains for the 2 tables with no `tenant_id` column at all (`campaign_targets`, `alumni_availability`) and the tables with `tenant_id` but no owner column and a `lead_id` (`admission_applications`, `alumni_connections`, `fee_payments`, `flyers`, `peer_review_bookings`, `students`, `travel_plans`, `visa_applications`, plus 2-hop `academic_risk_scores` and `payment_links`) — all verified against live schema, not assumed.
2. Confirmed live role data: `owner`, `admin`, `counselor` in production (`viewer` defined but unused); confirmed JWT claim shape (`userId`/`tenantId`/`role`) via `middleware/auth.js` and `routes/auth.js`.
3. Designed and drafted `01_PROJECT_REGISTRY/security-fixes/rls_54_tables_two_tier_lockdown.sql` — two-tier model per table group (see `DECISION_LOG.md`'s 2026-09-03 two-tier entry for the per-group reasoning), plus a `users_safe` view for `users` (excludes `password_hash`) and deliberately no policy at all on `tenants`/`users` (backend-only).
4. Applied live via `apply_migration` against `qovaakuithekhotkrrdi`.
5. Verified live, **17/17 PASS**: structural checks (`pg_policies` — every table exactly 1 policy, correctly named; `tenants`/`users` show zero) plus 9 role-simulation tests using `SET LOCAL ROLE authenticated` + `SET LOCAL request.jwt.claims` inside `BEGIN...ROLLBACK` transactions (including one live write-and-rollback test per join-chain table, to prove the ownership filter actually works, not just that it compiles) — admin/owner full-tenant visibility, counselor row-level scoping (direct-column and join-chain both), Group D tenant-wide-for-all-roles, `users_safe`'s owner-sees-all/self-only split, and structural confirmation `password_hash` cannot be selected from the view at all. Confirmed `postgres`/`service_role` still `rolbypassrls = true` and unrestricted data counts unchanged post-migration.

**What this did and did not change:** same shape as the 9-table fix — the backend (`postgres` connection) is completely unaffected; this only defines what `authenticated`-role access looks like, which remains dormant under the current custom-JWT auth model.

**Operational finding surfaced during verification (not a policy defect):** `leads.assigned_to` is `NULL` on all 785 production leads today — no lead is currently assigned to anyone. Verified live via `SELECT count(*), count(assigned_to) FROM leads GROUP BY tenant_id`. This means that the moment `authenticated` access ever goes live, every counselor/viewer would see **zero rows** on every ownership-column and lead-chain table (Groups A, C, C2, plus `campaign_targets`/`alumni_availability`) until leads are actually assigned — the two-tier policies are working exactly as designed (unassigned defaults to admin-only-visible, a safe default), but this is a real prerequisite, not just a theoretical one. See `NEXT_TASK.md`.

**Verification status: PASS** — 17/17, live-verified, not inferred from docs.

---

## 2026-09-06 — Exam Intelligence + Report Card System (ported into leadflow-ai)

**Phase context:** the owner had this feature built earlier on a separate, unrelated repo (`nepalmedtech-vinay/nepalmbbs-website`, branch `claude/exam-intelligence-report-card-tetbx6`) and asked for the same capability inside leadflow-ai itself, plus for leadflow-ai to be improved generally. This entry covers only the port; see `DECISION_LOG.md`'s 2026-09-06 entry for why it was built the way it was.

**What was found before building anything:** leadflow-ai's live schema (`qovaakuithekhotkrrdi`) already had `students`, `subjects`, `assessments`, `marks`, `attendance_records`, `academic_risk_scores`/`_config` — all real tables, 0 rows, wired to zero routes. `leads` already had `parent_name`/`parent_phone`/`parent_relation`/`alternate_phone`. `sharp` was already a backend dependency. None of this was assumed — confirmed live via `supabase-primary` before any code was written.

**What was built:**
1. Draft migration `backend/migrations/2026-09-06-exam-intelligence-report-cards.js` — adds `assessments.exam_group` (groups several subjects' assessment rows into one named exam sitting), plus 5 new tables: `report_templates`, `report_cards`, `mark_revisions`, `assessment_revisions`, `mark_imports`. **Not applied** — draft only, per instruction. Draft RLS at `01_PROJECT_REGISTRY/security-fixes/rls_exam_intelligence_tables.sql`, matching the existing two-tier model exactly (`report_cards`/`mark_revisions` follow `academic_risk_scores`'s student→lead→assigned_to join shape; `report_templates`/`assessment_revisions` follow `assessments`'s tenant-wide shape; `mark_imports` follows `marks`'s direct-`recorded_by` shape). **Also not applied.**
2. `backend/services/examIntelligence.js` — sheet parsing/validation/import, SQL-computed report figures (percentage/grade/rank/cohort average/previous-exam delta — never AI-computed), grounded-or-fallback AI narrative, guardian-phone normalization (never repaired, only flagged `suspect`), guarded assessment editing.
3. `backend/services/reportCardImage.js` — renders a report card as a PNG via `sharp` rasterizing an SVG string (no new image dependency), honoring a template's field selection/order/branding/footer rather than a fixed layout.
4. `backend/routes/exams.js` — import, cohort list, per-student report/generate/send, mark amendment, subject/assessment editing, template CRUD. Two-tier access enforced in the route itself (`canAccessStudent`), because the backend connects to Postgres as a role that bypasses RLS — the database-level policy above is real but dormant until this app issues Supabase-recognized sessions (same caveat as every other RLS entry in this file).
5. `backend/services/whatsapp.js` extended with `sendWhatsAppImage` (Meta Cloud API `type: image`), reusing the existing `WHATSAPP_TOKEN`/`WHATSAPP_PHONE_NUMBER_ID` credentials rather than a new integration.
6. Mobile: `exam_home_screen.dart`, `exam_import_screen.dart`, `exam_cohort_screen.dart`, `exam_report_screen.dart` — a new, independent top-level section ("Report Cards" in the More menu), deliberately not touching `lead_detail_screen.dart` or the Leads list at all, per the owner's explicit direction that this is a different job (enrolled-student results) from Leads (prospect follow-up).
7. `GET /exams/groups` + `GET /moreMenuItems`'s `DEFAULTS` array both extended (18th built-in item, `exam_intelligence`/"Report Cards") so the new section is reachable and individually customizable the same way every other More-menu tile already is.

**What was verified, and how:**
- `backend/scripts/verify-exam-intelligence.js` (new, since this backend has no test framework yet) — 12/12 checks pass: missing-max blocking, over-max refusal, deterministic grading, guardian-phone suspect-flagging (3 cases), AI-narrative number-grounding (accept/reject), and — critically — **`parseMarksSheetBuffer` against a synthetic fixture reproducing the exact structure of a real college result sheet** (multi-row merged header via forward-fill, per-subject inline max like `ANA(20)`, one paper's 4 subjects with no max stated at all, duplicate `Cell Number` columns, per-paper `Total`/`Result` columns) — the sheet's structure was inspected once (header rows only, never student data, already discarded) specifically to get this right instead of guessing at a simplified format.
- `renderReportCardPng` produces a valid, non-trivial PNG (verified via file signature + size), including with a custom template config (fewer fields, custom footer).
- `node --check` + a real `require()` on every new/modified backend file (with `npm install` actually run first — `node_modules` didn't exist in this checkout).
- `flutter analyze` on the full mobile project: **0 errors introduced** (the one pre-existing error, `test/widget_test.dart`, predates this session — untracked scaffolding file, unrelated). Only info-level lints on the new screens (`RadioListTile`'s deprecated `groupValue`/`onChanged` — already the established pattern elsewhere in this codebase, e.g. `team_screen.dart`, not a new anti-pattern).

**What was NOT verified (honestly, not glossed over):**
- No code here has been run against a real database — the new tables don't exist yet (migration undeployed by instruction), so `importMarks`, `computeReportCard`, `getOrCreateDefaultTemplate`, `updateAssessment`, and every route in `exams.js` are code-reviewed and syntax-checked, not executed.
- No real WhatsApp send was attempted (no live credentials/recipient in this environment).
- No mobile screen was rendered on a device/emulator — `flutter analyze` confirms it compiles cleanly, not that the UI looks or behaves correctly on screen.
- `read-excel-file`'s real-world behavior on an actual (not synthetic) `.xlsx` from a different spreadsheet program was not tested — only against `xlsx`-package-generated fixtures.

**A real bug caught and fixed during this work:** `parseMarksSheetBuffer` initially threw "File is empty or unreadable" against a perfectly valid fixture — `read-excel-file`'s Node build returns `[{ sheet, data }, ...]` rather than a flat row array (the exact same quirk `routes/leadsImportExcel.js` already works around), which this new function had not replicated. Caught by the verification script, not by inspection.
