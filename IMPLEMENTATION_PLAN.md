# IMPLEMENTATION_PLAN.md — realistic phased roadmap

Grounded in `PROJECT_AUDIT.md`, `ARCHITECTURE_MAP.md`, `FEATURE_STATUS.md`, `TECH_DEBT.md`. Re-sequenced from the Master Spec's own Phase 0–12 to front-load what's fastest-and-safest given what already exists, per your three decisions: **(1)** audit first then continue building, **(2)** web primary + Flutter mobile as companion, **(3)** no paid infra yet — build adapters, mark "Not Connected" honestly.

**Scale reality check, stated plainly:** the Master Spec describes a multi-quarter build for a small team. Nothing below claims this gets "done" in one pass. Each phase is scoped to be a real, shippable, independently useful increment — not a slice of an unfinished whole.

---

## Phase 1 — Web Foundation + Schema Hardening

The two prerequisites everything else depends on.

**1a. Bootstrap the web frontend.**
Recommended stack (stated as a decision, not a question — this is an engineering choice, not a business one): **Next.js (App Router) + TypeScript + Tailwind**, talking to the *existing* Express backend (no backend rewrite — same API, new client). Reasoning: fastest path to the sidebar/Command-Center UX §25–27 describes, large ecosystem, deploys cleanly to Vercel or alongside the existing Render setup. Ships as `web/` alongside `backend/` and `mobile/` in this same repo.
First real screens (not placeholders): login (reuses existing `/auth` endpoints), Dashboard, CRM (leads list + detail) — i.e., prove the web app can do everything the mobile app already does for the core CRM before adding anything net-new.

**1b. Schema hardening** (from `TECH_DEBT.md` §1–3).
Snapshot the real live schema into `SCHEMA_SNAPSHOT.sql`. Add transaction support to `db.js`. Any new table from this point (Organization/Workspace, RBAC roles, AI worker registry, job queue, event log) goes through a real migration file, reviewed, never inline `CREATE TABLE IF NOT EXISTS` again.

**1c. Multi-level tenancy + full RBAC.**
Add `organizations` and `workspaces` tables; migrate existing `tenants` rows into one workspace each under a new org (non-destructive — existing data keeps working under the old flat model during transition). Expand roles from 3 to the spec's 8, and audit-gate the destructive routes `TECH_DEBT.md` §3 flagged.

**Definition of done for Phase 1:** a counselor can log into the *web* app, see the same leads/pipeline the mobile app shows, and the schema has a real migration history from this point forward.

---

## Phase 2 — AI Worker Framework + Orchestrator (formalize what already exists)

This is the fastest-to-real-value phase because 4 real workers already exist informally.

- Define the worker interface (§8's schema: id/role/objective/tools/permissions/memory/triggers/input-output schema/confidence/audit trail/retry/approval) as a real TypeScript/JS interface + a `workers` registry table.
- Wrap the 4 existing informal workers (`aiAnalysis.js` → Lead Intelligence Worker, `leadScoring.js` → Lead Qualification Worker, `smartTriage.js` → a Follow-up/Support Worker, `predictions.js` → part of Analytics Worker) in this interface — this is refactoring real working code into a formal shape, not writing new AI logic from scratch.
- Build the Orchestrator as a thin layer that takes a business objective, picks a worker, and records the execution (inputs, outputs, cost estimate, confidence) — start with rule-based worker selection (objective type → worker), not a second LLM call to pick a worker, until there's a real need for that complexity.
- Add the simplest possible job queue: a `jobs` table + a polling worker process (no Redis needed yet — Postgres `SELECT ... FOR UPDATE SKIP LOCKED` is a legitimate, infra-light queue for this scale). Upgrade to Redis/BullMQ only if/when volume actually demands it.

**Definition of done:** the web (and mobile) app can show "AI Workforce Command Center" (§26) with real worker status/history, because the 4 existing workers are now instrumented, not because new ones were invented.

---

## Phase 3 — Opportunity Radar + Lost Lead Autopsy (the flagship features)

The two features named explicitly as flagship in the Master Spec (§12–13, §34), and the ones with the clearest, most immediate business value for an MBBS-admissions consultancy specifically.

- Opportunity Radar: a scheduled job (using Phase 2's queue) that scans leads for the concrete signals §12 lists (inactive, high-value, unanswered, delayed follow-up) — all of which are already queryable from the existing `leads`/`communications`/`reminders` tables, no new data collection needed — and writes `opportunities` rows.
- Lost Lead Autopsy: for leads marked lost/inactive, run the existing `aiAnalysis`/`leadScoring` workers over their full history and produce the WHY LOST → EVIDENCE → RECOVERY STRATEGY output §13 specifies, with explicit confidence marking on uncertain conclusions (per the spec's own rule).
- Both surface as real UI: Opportunity Center (§27) on web, with Review/Approve/Execute/Schedule/Dismiss actions gated by Phase 1's human-in-the-loop approval levels for anything that sends outbound messages.

**Definition of done:** the Master Spec's own flagship user story ("recover my inactive leads and create a campaign") works end-to-end through steps 1–8 (identify → segment → analyse → recovery strategy → messages) using real data. Steps 9+ (creative asset generation, execution, tracking) depend on Phase 4+.

---

## Phase 4 — Knowledge/RAG upgrade

Turn `knowledge.js`'s flat article storage into real retrieval: add embeddings (via whichever provider is actually connected per your BYOK decision — `aiProvider.js` already has the provider-swap pattern, extend it with an `embed()` method), pgvector extension on the existing Postgres (no new infra service required — pgvector ships as a Postgres extension, Supabase supports it), chunk/store/retrieve/rerank pipeline. Smart Triage upgrades from keyword-ish matching to real vector search for free once this lands.

## Phase 5 — Event bus + real webhook system

Promote `automationEngine.js`'s in-process `fireEvent()` into a durable `events` table (append-only log) with real outbound webhook subscriptions (signatures, retries, delivery logs) per §17's event list. This unlocks the n8n adapter as an optional consumer of the same event stream, satisfying §16's "n8n optional, native fallback required" without native and n8n being two separate code paths.

## Phase 6 — Creative/Campaign engine expansion

Only once a real image/video provider is connected (per your "Not Connected until real credentials" decision) — build the adapter first, gated behind a clear "not connected" state in both web and mobile UI, then wire the brief→script→storyboard→asset pipeline once credentials exist. Flyer/Logo Studio (already built, this session) becomes one input into this pipeline rather than a separate tool.

## Phase 7 — Credit/Billing engine

Only meaningful once Phase 2's worker executions are real and countable — track token/generation usage per execution (the `jobs` table from Phase 2 already has the natural place to record this), then layer plans/limits/top-ups on top. Do not build this before there's real usage to meter.

## Phase 8 — Observability + hardening

Structured logging, provider-latency/failure tracking, admin diagnostics screen, staging environment (per `TECH_DEBT.md` §7), automated test suite backfilled across Phases 1–7's new code (and ideally the highest-risk existing routes too — payments, auth, bulk actions).

---

## What's deliberately not sequenced yet

Full video generation, n8n's actual UI-based workflow builder (vs. its webhook adapter), and multi-currency/multi-region billing are real spec sections but have no forcing function yet (no connected provider, no paying customers on a metered plan) — build them when a concrete need appears, not speculatively.

## Immediate next step

Recommend starting **Phase 1a (web frontend bootstrap)** and **Phase 1b (schema snapshot + transaction support)** in parallel next — 1b is low-risk and fast, 1a is the long pole that every later phase's web UI depends on. Say the word and I'll start scaffolding the Next.js app + write the schema snapshot script.
