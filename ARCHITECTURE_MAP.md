# ARCHITECTURE_MAP.md — LeadFlow AI current architecture

## System diagram (current, as of this audit)

```
┌─────────────────────────┐         ┌──────────────────────────────┐
│   Flutter Mobile App     │  HTTPS  │   Express Backend (Render)    │
│   (Android + Web/PWA)    │────────▶│   backend/server.js            │
│   mobile/lib/ (66 screens)│         │   61 route files               │
└─────────────────────────┘         │   18 service files             │
                                      │                                 │
        (NO WEB APP EXISTS YET)      │  middleware/auth.js             │
                                      │  (attachUser → enforceAuth)     │
                                      └───────────────┬────────────────┘
                                                       │
                                      ┌────────────────▼────────────────┐
                                      │  Postgres (Supabase)             │
                                      │  via backend/db.js (pg + shim)   │
                                      └───────────────────────────────────┘
                                                       │
                          ┌────────────────────────────┼─────────────────────────┐
                          ▼                             ▼                         ▼
                 Supabase Storage            aiProvider.js (Claude/           WhatsApp Cloud API
                 (documents, logos,          Gemini/OpenRouter,               (webhook + send),
                 voice notes, flyer          via generateJson())              Razorpay/eSewa/Khalti
                 renders — signed URLs)                                       (fee collection)
```

## Backend: route inventory (61 files, `backend/routes/`)

Grouped by the Master Spec system each maps closest to:

**CRM / Lead Intelligence (§5)**
`leads.js`, `leadsImport.js`, `leadsImportExcel.js`, `leadsExcelV2.js`, `leadFolders.js`, `leadNotes.js`, `leadTimeline.js`, `lead360.js`, `leadDetailSections.js`, `leadListFields.js`, `pipelineStages.js`, `customFields.js`, `scoring.js`, `students.js`, `admissions.js`

**Communication (part of §5 + §21)**
`communications.js`, `whatsapp.js`, `whatsappLink.js`, `whatsappWebhook.js`, `email.js`, `calls.js`, `voiceNotes.js`, `inbox.js`, `notifications.js`

**AI (§8–10, narrow/single-purpose today)**
`ai.js` (theme gen, restyle, icon-find, emoji-suggest, lead analysis dispatch), `triage.js` (Smart Triage), `predictions.js` (admission matching)

**Scheduling / Ops**
`tasks.js`, `reminders.js`, `calendar.js`, `meetings.js`, `automations.js`, `audit.js`, `performance.js`

**Business config / Business OS (§4)**
`settings.js`, `colleges.js`, `alumni.js`, `campaigns.js`, `journey.js`, `compliance.js`, `fees.js`

**Content/Design tools (Flyer + Logo Studio, this session's work)**
`flyerProjects.js`, `flyers.js`, `tenantLogos.js`, `moreMenuItems.js`, `shareTargets.js`, `dashboardSections.js`

**Knowledge (§7, shallow today)**
`knowledge.js`

**Payments (fee collection, not billing/credits)**
`payments.js`, `peerReviews.js`, `reviewProviders.js`

**Social/growth**
`social.js`, `capture.js`, `leadAdsWebhook.js`

**Auth / Infra**
`auth.js`, `cockpit.js`, `callPrep.js`

## Backend: service layer (18 files, `backend/services/`)

| File | Role | Spec mapping |
|---|---|---|
| `aiProvider.js` | Provider-agnostic `generateJson()` over Claude/Gemini/OpenRouter | §10 (partial — text only, no image/video/embeddings) |
| `aiAnalysis.js` | Per-lead AI analysis (sentiment, next-best-action) | §8 Lead Intelligence Worker (informal) |
| `leadScoring.js` | Configurable weighted lead scoring | §8 Lead Qualification Worker (informal) |
| `smartTriage.js` | WhatsApp auto-reply from Knowledge Base | §8 (a real, narrow worker) |
| `automationEngine.js` | `fireEvent()` — trigger→action rules | §16 native automation engine (real seed) |
| `duplicateDetection.js` | Fuzzy lead-duplicate matching | — |
| `engagementTrend.js` | Engagement scoring over time | §28 Analytics (partial) |
| `facebookLeadAds.js` | Meta Lead Ads webhook ingestion | §5 lead source |
| `whatsapp.js`, `email.js` | Channel send helpers | §21 Distribution (partial) |
| `payments.js` | Razorpay/eSewa/Khalti fee collection | unrelated to §19 (billing is AI/compute usage, not student fees) |
| `logoTemplates.js`, `flyerTemplates.js`, `fontSetup.js` | Design-tool rendering (SVG→PNG via `sharp`) | §11 Creative (image only, no video) |
| `lead360.js` | Aggregated per-lead view | §5 |
| `phone.js`, `crypto.js`, `supabaseStorage.js` | Utilities | — |

## Auth & tenancy model (current)

- `users` table: `id, tenant_id, email, password_hash, full_name, role`. Role is a free-text column, values in practice: `admin`, `counselor`, `viewer`.
- `tenants` table: single flat table, one row per business. **No Organization → Workspace hierarchy** — §23's model is two levels deeper than what exists.
- `middleware/auth.js`: `attachUser` (decodes JWT, sets `req.user`), `enforceAuth` (blocks any non-public path without `req.user`), `requireRole(...)` (exists, used in 4 places only), `PUBLIC_PREFIXES` allowlist (login/register, public capture forms, UPI pay page, inbound webhooks, short links).
- Mobile stores the JWT + `tenantId` in `SharedPreferences` (`mobile/lib/services/api_service.dart`'s `authToken`/`tenantId` statics), sent as `Authorization: Bearer` + `x-tenant-id` on every request (both headers required after this session's audit found and fixed 11 file-upload call sites that were missing the Authorization header).

## Data layer

- Postgres via Supabase, accessed through `backend/db.js` — a deliberate SQLite-syntax-compatible shim (`?` placeholders, `datetime('now')` translated), because the codebase was originally `node:sqlite` and ported later. This is a real piece of technical debt (see `TECH_DEBT.md`) but also means the query surface is simple and portable.
- Only **11 dedicated migration files** (`backend/migrations/`) — most tables are created inline via `CREATE TABLE IF NOT EXISTS` at the top of their owning route file (confirmed pattern: `dashboardSections.js`, `leadListFields.js`, etc.). This means there is no single authoritative schema file or migration history for most of the ~60+ tables — a real audit gap, not just an inconvenience (see `TECH_DEBT.md`).
- No vector/embeddings store of any kind.

## Mobile app (`mobile/`)

- Flutter, 66 screens under `mobile/lib/screens/`.
- State: `provider` package — `AppearanceSettings`, `GlassSettings`, `LabelOverrides`, `LocaleSettings`, `EditModeSettings` (added this session) as app-wide `ChangeNotifier`s.
- `mobile/lib/services/api_service.dart` — single `ApiService` class, ~150+ methods, one per backend endpoint, hand-written (no codegen/OpenAPI client).
- CI: `.github/workflows/build-and-release.yml` — builds APK + web/PWA on every push to `main` or manual dispatch, publishes to GitHub Releases + GitHub Pages.
- This session's work (Flyer/Logo Studio freeform canvas editor, Settings Studio, AI Quick Restyle, Edit Mode live overlay, 48-icon library + AI Icon Finder) all lives here and is directly reusable as "the mobile companion app" per your platform decision — no rework needed for that role.

## What does NOT exist anywhere in the repo

- Web frontend (any framework).
- Job queue / background worker infrastructure (no Redis, no `bullmq`/`bee-queue`/`agenda` in `package.json`).
- Event bus / durable outbound webhook delivery system.
- Vector database or embeddings pipeline.
- Video/audio generation integration, FFmpeg.
- n8n client/adapter.
- Credit/usage ledger for AI costs.
- Automated test suite (`backend/package.json`'s `"test"` script is the npm default placeholder — `echo "Error: no test specified" && exit 1`).

## Deployment

- Backend: Render, auto-deploys on push to `main` (confirmed this session: merging a PR triggered a live backend redeploy).
- Mobile: GitHub Actions → GitHub Releases (APK) + GitHub Pages (web/PWA build of the *Flutter* app, not a separate web product).
- No staging environment, no infra-as-code, no monitoring/observability stack found.
