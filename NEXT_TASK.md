# NEXT_TASK.md — LeadFlow AI

What needs to happen next, and why. See `IMPLEMENTATION_PROGRESS.md` for what's
already done, `DECISION_LOG.md` for why things were sequenced the way they
were, `TECH_DEBT.md` for known issues not yet addressed.

---

## Newest — Exam Intelligence + Report Card System needs review before anything goes live

**Landed:** 2026-09-06, on the working tree only — nothing committed, nothing
applied to the database. See `IMPLEMENTATION_PROGRESS.md` (2026-09-06 entry)
for exactly what was built and verified, and `DECISION_LOG.md`'s matching
entry for why it's shaped the way it is.

**Before this can be used at all:**
1. Review `backend/migrations/2026-09-06-exam-intelligence-report-cards.js`
   and `01_PROJECT_REGISTRY/security-fixes/rls_exam_intelligence_tables.sql`
   — both draft-only. Apply the migration first, then the RLS, then verify
   (structural checks + role-simulation, same pattern as the 54-table fix)
   before trusting either is live.
2. Review the actual code changes (`git status`/`git diff` — nothing was
   committed) and decide what to commit.
3. **Gemini key**: `backend/.env` has `GEMINI_API_KEY`/`AI_PROVIDER=gemini`
   set locally and was smoke-tested directly against Google's API
   (`gemini-3.6-flash` — note `gemini-2.0-flash`, `aiProvider.js`'s old
   default, is retired; already fixed in code). This key was pasted into a
   chat window earlier in this session and should be treated as public —
   rotate it before relying on it for anything real.
4. **WhatsApp**: `sendWhatsAppImage` reuses the existing
   `WHATSAPP_TOKEN`/`WHATSAPP_PHONE_NUMBER_ID` — if those aren't set, every
   send attempt fails with a clear "not configured" error rather than
   silently doing nothing; nothing new to configure beyond what the
   existing WhatsApp integration already needed.
5. **No end-to-end run yet.** Nothing here has touched a real database, a
   real WhatsApp send, or a real device/emulator screen — see
   IMPLEMENTATION_PROGRESS.md's "what was NOT verified" list. The first
   real import + generate + send should be watched closely.

**Next chunk, if this continues (in the order the value falls):**
1. A template-editing UI — the backend (`GET/POST/PATCH /exams/templates`)
   and render logic (`reportCardImage.js` honors `fields`/`subjectOrder`/
   `branding`/`footerText`/`disclaimer`) are both ready; there's no mobile
   screen yet to actually edit a template's config, only to select
   between whatever already exists via `template_id`.
2. Student photo on the card — `students` has no photo column yet; the
   reference implementation flagged the same gap independently.
3. A real server-side PDF, if a college needs a filed PDF per student —
   today's card is a PNG image, sendable and printable, but not a PDF.
4. Cohort/bulk send — today a coordinator opens one student at a time.
   Keep the per-send guardian-confirmation guard if this is built; that
   check is the feature, not overhead (same principle the reference
   implementation insisted on).
5. Manual marks entry for a college with no spreadsheet — everything
   currently assumes an import; a small per-subject entry form would need
   to go through the exact same conflict/revision path as re-import, not
   a direct write to `marks`.

---

## `leads.assigned_to` is unpopulated in production

**Surfaced:** 2026-09-03, during live verification of the two-tier RLS
policy rollout (`01_PROJECT_REGISTRY/security-fixes/rls_54_tables_two_tier_lockdown.sql`).

**What's true today:** every one of the 785 leads in production
(`demo-consultancy` tenant) has `assigned_to = NULL`. Verified live:
`SELECT count(*), count(assigned_to) FROM leads GROUP BY tenant_id` →
`785, 0`.

**Why this matters:** the two-tier RLS model just shipped (owner/admin see
all tenant data; every other role sees only their own assigned/created
records) uses `leads.assigned_to` as the root of ownership for `leads`
itself and for 10 other tables that inherit visibility through it
(`admission_applications`, `alumni_connections`, `fee_payments`, `flyers`,
`peer_review_bookings`, `students`, `travel_plans`, `visa_applications`,
`academic_risk_scores`, `payment_links`, plus `campaign_targets` and
`alumni_availability`). An unmatched (NULL) ownership column correctly
defaults to owner/admin-only visibility under this policy — a safe design,
not a bug — but the practical consequence is: **with zero leads currently
assigned, a counselor or viewer role would see zero rows across all of
those tables**, the moment `authenticated`-role access ever becomes live
for this project (it's dormant today — see `TECH_DEBT.md` §2's dormancy
caveat; this app's custom JWT auth doesn't reach Supabase's `authenticated`
role yet).

**What needs to happen before this matters in practice:** leads need to
actually get assigned to counselors through the app's normal workflow (the
`assigned_to` field already exists and is used elsewhere in the UI/API —
this isn't a schema gap, just a data-population gap). No urgency while
`authenticated` access stays dormant, but this should be resolved (or at
least tracked as a known blocker) before/alongside whatever work eventually
makes real per-user Supabase sessions active, since that's the point these
policies stop being dormant and start actually gating counselor accounts.

**Not blocking any current work** — flagged here so it isn't forgotten
between now and whenever `authenticated`-role access becomes real.
