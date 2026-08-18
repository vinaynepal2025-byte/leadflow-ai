# TECH_DEBT.md — real issues found during Phase 0 audit

Ordered roughly by how much they'll bite once AI Workforce OS work starts.

## 1. No tracked schema — most tables live only as inline `CREATE TABLE IF NOT EXISTS`

Only 11 files in `backend/migrations/`, but ~60+ tables exist in production. The rest are created the first time their owning route file loads (confirmed pattern in `dashboardSections.js`, `leadListFields.js`, and almost certainly most others). This means:
- There is no single file you can read to see the real current schema.
- Two route files could theoretically define the same table differently if not careful.
- Any new Organization→Workspace tenancy model (§23) or RBAC role table (§24) needs to be introduced as a **real, reviewed migration**, not another inline `CREATE TABLE IF NOT EXISTS` — this is the first thing Phase 1 should fix, before adding more tables on the same shaky foundation.

**Done:** `SCHEMA_SNAPSHOT.md` now exists — generated read-only via the Supabase MCP server against the live `leadflow-ai` project. Real numbers: 56 tables, 4 tenants, 785 leads. All new tables from this point forward go through `backend/migrations/`, reviewed, never another inline `CREATE TABLE IF NOT EXISTS`.

## 2. SQLite-shim (`db.js`) masks real Postgres capability

`backend/db.js` translates `?` placeholders and `datetime('now')` for Postgres compatibility, but this means:
- No transactions are used anywhere (the shim has no `BEGIN`/`COMMIT` wrapper) — multi-step writes (e.g., "create lead + fire automation + log activity") are not atomic. A crash mid-sequence leaves partial state.
- JSONB columns are used as plain strings passed through `JSON.stringify`/`JSON.parse` at the call site rather than native Postgres JSON operators — fine for full-document replace (how `canvas_json` is used), but blocks anything that wants partial JSON updates or JSON-path queries (relevant once Business Memory §6 needs structured, queryable facts).
- **Tenant isolation is 100% application-code discipline, and this is now verified, not just inferred.** 54 of 56 tables show `rls_enabled = true` in Supabase, which looked like real protection at first glance — but `pg_policies` returns zero rows for every table (`SCHEMA_SNAPSHOT.md`'s RLS finding). Postgres denies all access on an RLS-enabled table with no policies, *except* for roles with `BYPASSRLS` — and the `postgres` role `db.js` connects as (`PGUSER || 'postgres'`) has `rolbypassrls = true`, confirmed by querying `pg_roles`. **RLS is fully bypassed on every request the backend makes.** It provides zero actual protection today; the `WHERE tenant_id = ?` clause in each route file is the only real isolation boundary. One missed clause in one query is a genuine cross-tenant data leak, right now, in production — worth a systematic grep-audit of every query touching a tenant-scoped table before Organization→Workspace tenancy adds a second isolation dimension on top.

**Not urgent to replace the shim wholesale** — it works and rewriting 61 route files' worth of queries is its own large, risky project. Do add transaction support to the shim (`db.transaction(async (tx) => {...})`) before any multi-table AI Workforce write (e.g., worker execution + audit log + credit debit) is built, since that's exactly the kind of multi-step write that needs atomicity.

## 3. RBAC is declared but barely enforced

`requireRole()` is implemented correctly in `middleware/auth.js` but called in only 4 route handlers app-wide. Every other authenticated route only checks "is there a valid token for this tenant," not "is this user's role allowed to do this." Before RBAC expands to 8 roles (§24), audit which of the 61 route files contain destructive or sensitive actions (delete, bulk actions, billing, settings) and are missing a `requireRole()` gate today.

## 4. No automated tests

`backend/package.json`'s `test` script is the unconfigured `npm init` default. Given the Master Spec's own Definition of Done (§39) requires tests to pass before declaring anything complete, Phase 1 should stand up a minimal test harness (even just `node --test` + `supertest` against a test tenant, no new framework needed) before Phase 2+ features start shipping — otherwise "tests pass" can never honestly be checked off.

## 5. `mobile/lib/services/api_service.dart` is a single ~150-method hand-written file

Every backend endpoint has a hand-written Dart method with manually-typed headers/body. This works today but:
- Nothing catches a backend route signature change breaking the mobile app until runtime.
- Adding a full web frontend (per your platform decision) means either hand-writing the *same* API client again in TypeScript, or generating both from a shared OpenAPI/schema definition. Worth deciding this once, in Phase 1, rather than accumulating two independently-drifting API clients.

## 6. Found and fixed this session (already resolved, noted for the record)

- **11 file-upload endpoints (documents, voice notes, logos, flyer assets) were silently sending no `Authorization` header**, failing every upload with a 401 for any logged-in user once the backend's global `enforceAuth` gate went live. Root cause: `MultipartRequest` calls each hand-built their own headers map instead of reusing the shared `_headers` getter. Fixed by introducing `_multipartHeaders` and pointing all 11 sites at it. This class of bug (a second, incomplete copy of an auth header map) is worth grep-auditing for elsewhere before Phase 1 adds more authenticated write paths.
- A `FloatingActionButton` in Flyer/Logo Studio could visually overlap the toolbar on longer button labels — fixed by moving it into normal document flow. Noted only because it's the kind of "floating UI over dynamic content" pattern worth avoiding in the new web frontend's layout system too.

## 7. Deployment has no staging environment

Every push to `main` on the backend deploys straight to the live Render service serving real tenants. Given the scale of Phase 1+ (auth/tenancy changes, new tables, potentially new services), introduce a staging Render service (or at minimum, a documented manual pre-deploy checklist) before schema-changing PRs start merging — a bad migration on a live single-environment setup is the highest-blast-radius mistake available.

## 8. No provider-key configuration visibility for the business owner

`GET /ai/provider` exists and reports whether a key is configured, but there's no equivalent for the *other* providers the new work needs (image/video gen, payment gateway credentials, future n8n webhook URL). Per your "adapters only, mark Not Connected" decision, each new adapter should ship with the same honest status-reporting pattern `ai.js` already established, from day one.
