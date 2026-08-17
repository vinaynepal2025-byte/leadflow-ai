# PROJECT_AUDIT.md — LeadFlow AI → AI Workforce OS
**Audit date:** 2026-08-17 · **Auditor:** Claude (Phase 0, per LEADFLOW_AI_WORKFORCE_OS_MASTER_SPEC.md)
**Scope of this audit:** read-only. No live phone numbers, WhatsApp numbers, or real lead data were contacted or modified — every finding below comes from static code reading (route files, migrations, package.json, mobile screens), never from running a request against production.

## 1. What LeadFlow AI actually is today

LeadFlow AI is a **mature, working, single-tenant-per-business CRM for education/admissions consultancies** (MBBS admissions is the primary real-world use case already in production), built as:

- **Backend:** Node.js/Express 5, Postgres (via Supabase), deployed on Render (`https://leadflow-ai-backend-e50r.onrender.com`). No ORM — a thin SQLite-syntax-compatible shim (`backend/db.js`) over `pg`, because the app was originally written against `node:sqlite` and migrated later.
- **Frontend:** a single Flutter mobile app (Android + Web/PWA build), 66 screens, built and released via GitHub Actions on every push (`build-and-release.yml`) — **no separate web dashboard exists**.
- **Auth:** real JWT-based auth (`backend/middleware/auth.js`, `backend/routes/auth.js`) — register/login, bcrypt password hashing, 30-day tokens, `enforceAuth` gate on every non-public route. Genuinely production-grade for what it does.
- **AI:** a real provider-abstraction layer (`backend/services/aiProvider.js`) — swappable between Claude/Gemini/OpenRouter via env vars, used by ~8 features (lead analysis, theme generation, emoji suggestion, icon finding, section restyling, etc.) via one shared `generateJson()` helper.
- **61 backend route files**, 18 backend service files, 66 Flutter screens — this is a large, feature-rich application, not a prototype.

Per the existing `MODULES_STATUS.md` (repo root, predates this audit), **32 core CRM modules are built and tested**, plus a second wave of "futuristic ecosystem" features already shipped: WhatsApp Smart Triage (AI auto-reply from Knowledge Base), Predictive Admission Matching (ranks colleges from the tenant's own historical offer/rejection data), Unified Inbox, Alumni Network, Consent & Compliance (GDPR-style export/erasure), Payment Gateways (Razorpay/eSewa/Khalti — real API contracts, needs the business's own merchant credentials), and a genuinely deep in-app UI customization engine (themes, per-screen/per-button live restyling, AI-assisted restyling) built across this session.

**Bottom line: this is not a blank slate.** Large parts of the Master Spec's vision already exist in embryonic or working form under different names. The gap is real but narrower than "build everything from zero" — see `FEATURE_STATUS.md` for the section-by-section mapping.

## 2. The single biggest structural gap: there is no web frontend

The Master Spec's UI/UX section (§25–27: sidebar nav, "AI Workforce Command Center", "Opportunity Center") describes a desktop SaaS web dashboard. **Nothing like this exists in the repo today** — confirmed by a repo-wide search for `.jsx`/`.tsx`/`next.config`/`vite.config`: zero results. Everything the business and its counselors use today is the Flutter mobile app.

Per your decision (web primary, mobile companion), Phase 1 must include **bootstrapping an entirely new web application from scratch** — this is the largest single new piece of work in the whole roadmap, bigger than any individual AI Workforce feature.

## 3. What's genuinely absent (not just "different name, same thing")

These have **no equivalent** anywhere in the current codebase:

- A formal AI worker framework (registry, tool/permission/memory/audit schema per worker) — current AI features are one-off functions, not workers with state.
- An orchestrator that decomposes objectives into worker tasks.
- Real RAG (embeddings + vector retrieval) — `knowledge.js` (79 lines) stores/serves FAQ articles as plain text; Smart Triage does keyword-ish matching, not vector search.
- A job/queue system (§18) — no `bullmq`/`bee-queue`/Redis in `package.json`. Long AI calls run synchronously in the request/response cycle today.
- An event bus / outbound webhook system (§17) — `automationEngine.js`'s `fireEvent()` is real and working, but it's an in-process function call fired from within route handlers, not a durable, subscribable event log.
- A credit/billing ledger for AI/compute usage (§19) — `payments.js` handles one-off UPI/Razorpay/eSewa fee collection *from students*, unrelated to metering the business's own AI usage.
- Video/image/voice generation pipeline (§11) — no FFmpeg, no image/video-gen SDK.
- n8n adapter (§16) — not present, though the native fallback (`automationEngine.js`) is a real, working starting point per the spec's own "n8n optional, native fallback required" rule.
- Multi-level tenancy (Organization → Workspace) (§23) — `tenants` is a single flat table; one tenant = one business, no workspace sub-grouping.
- Full 8-role RBAC (§24) — `requireRole()` exists and works, but is only called in 4 places app-wide; the real role set in use is 3 values (`admin`/`counselor`/`viewer`), not the spec's 8.
- The web frontend itself (see §2 above).

## 4. What's real, working, and directly reusable

- JWT auth + tenant isolation pattern — extend, don't replace.
- `aiProvider.js`'s `generateJson()` abstraction — this *is* the right shape for §10's provider abstraction; needs more provider types (image/video/embeddings) and routing logic, not a rewrite.
- `automationEngine.js`'s `fireEvent()` — the real seed of §16's native automation engine.
- `leadScoring.js`, `predictions.js`, `aiAnalysis.js`, `smartTriage.js` (services) — each is a legitimate, narrow AI worker already; formalizing them under a shared worker interface (§8) is additive, not a rewrite.
- The full CRM data model (leads, pipeline, activities, communications, documents) — this is §5 already built.
- The entire mobile app and its 66 screens — becomes the "mobile companion" per your platform decision, largely as-is.

## 5. Immediate safety note (per your instruction)

No route was invoked against the real Render backend or the production database during this audit. Any future testing phase must continue to avoid real phone numbers/WhatsApp numbers already present in production data — use synthetic test leads/tenants only.

See `ARCHITECTURE_MAP.md` for the full technical inventory, `FEATURE_STATUS.md` for the section-by-section spec coverage table, `TECH_DEBT.md` for what needs fixing along the way, and `IMPLEMENTATION_PLAN.md` for the realistic phased build order.
