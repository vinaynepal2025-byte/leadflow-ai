# NEXT_TASK.md — LeadFlow AI

What needs to happen next, and why. See `IMPLEMENTATION_PROGRESS.md` for what's
already done, `DECISION_LOG.md` for why things were sequenced the way they
were, `TECH_DEBT.md` for known issues not yet addressed.

---

## Newest — WhatsApp hyperlink send for report cards, built + verified (2026-09-07, later same day)

**Decision (Vinay, 2026-09-07):** the paid Meta Cloud API path (`POST
.../send`, `sendWhatsAppImage`) stays dormant/future — only build it once a
paid WhatsApp Business tier is actually taken. For now, report cards use the
same free semi-automatic `wa.me` hyperlink pattern already proven for leads
(`routes/whatsappLink.js`) and flyers (`routes/flyerProjects.js`'s
`/share-link`): a button prepares everything, a human taps Send in WhatsApp.

**Built and verified end-to-end against the live backend (commits `d5455f7`,
`3969e86`), smoke-tested with a throwaway fixture then fully cleaned up
(all exam-intelligence tables back to 0 rows):**
- `leads.father_name`/`father_phone`/`mother_name`/`mother_phone` added
  (migration `2026-09-07-lead-father-mother-contacts.js`, applied live).
- The sheet parser now actually extracts Father's/Mother's Name+Cell Number
  (previously recognized but deliberately ignored) and backfills them onto
  the matched lead **only where empty** — never overwrites a counselor's
  correction. Verified: import with real father/mother columns correctly
  populated `leads.father_phone = '+917080800888'` etc.
- `GET /exams/:examGroup/students/:studentId/whatsapp-link?guardian=father|mother`
  returns a working `wa.me` link with a 7-day signed image URL embedded in
  the pre-filled message. Verified against a real number — link resolved
  correctly to `wa.me/917080800888` with the right message text.
- `POST .../whatsapp-link/confirm-sent` logs to `communications` and marks
  the report card `sent`, mirroring `whatsappLink.js`'s confirm-sent pattern.
- **Two real bugs found and fixed during this test:**
  1. Report card header showed the raw `tenant_id` ("demo-consultancy")
     instead of `tenants.name` ("Demo Consultancy") — fixed in
     `routes/exams.js`'s `/generate`.
  2. "Batch average: 162%" was mislabeled — `batchAverage` is a raw total
     (sum of `marks_obtained`), not a percentage. Now renders as "162/200"
     matching each subject row's style. Fixed in `services/reportCardImage.js`.
  Both fixed and visually re-verified (downloaded and viewed the actual
  rendered PNG before and after).
- **One real infrastructure bug found and fixed (with Vinay's explicit
  approval — this one needed it, a production RLS policy change):** the
  `leadflow-uploads` Supabase Storage bucket only had `INSERT`/`SELECT`
  policies, no `UPDATE` — so re-uploading to an already-used storage path
  (regenerating any report card, or re-rendering a flyer/logo) failed with
  `AccessDenied`. Fixed by adding a matching `UPDATE` policy (same scope:
  `bucket_id = 'leadflow-uploads'`, same `public` role) — additive only,
  nothing existing changed. This was blocking more than just report cards.

**Still open:**
1. **Mobile UI not built yet.** The per-student "Send to Father"/"Send to
   Mother" buttons only exist as backend endpoints today — no screen calls
   them. This is the next real chunk: a cohort/report-card list screen
   (`GET /exams/:examGroup/cohort` already exists) with Generate + the two
   WhatsApp buttons per row, `launchUrl` on the returned `whatsapp_link`,
   then `confirm-sent` after the user returns to the app.
2. **Gemini narrative still broken in production** (see the entry below) —
   unrelated to this feature; the safe fallback sentence is used either way.
3. Cloud API auto-send (`WHATSAPP_TOKEN`/`WHATSAPP_PHONE_NUMBER_ID`) stays
   deliberately unconfigured — only revisit when a paid WhatsApp Business
   tier is actually purchased.

---

## Exam Intelligence + Report Card System: end-to-end smoke test done (2026-09-07)

**Landed:** 2026-09-06, committed (`1ebb93c`). Migration and RLS are both
**applied and live** — confirmed 2026-09-07 via the `supabase-primary` MCP:
`subjects`/`assessments`/`marks`/`report_cards`/`mark_imports`/etc. all exist
in `qovaakuithekhotkrrdi` with `rls_enabled = true`. (Earlier note below this
one previously said "nothing committed, nothing applied" — that was true as
of 2026-09-06 but is now stale; superseded by this entry.)

**2026-09-07 smoke test (real import → compute → generate → send, against
the live Render backend + Supabase, using a throwaway `smoke-test-lead-001`/
`smoke-test-student-001` fixture, cleaned up afterward — all tables back to
0 rows):**

1. **Import + compute: PASS.** POST `/exams/import` with a 2-subject xlsx
   (Anatomy 78/100, Physiology 84/100) inserted cleanly. GET `.../report`
   computed 81% / grade A / rank 1 of 1 — arithmetic verified by hand,
   correct.
2. **Report card generation: PASS.** POST `.../generate` rendered the PNG
   and uploaded it to Supabase Storage with no error; `report_cards` row
   landed with `status: 'ready'`.
3. **Gemini narrative: FAILING SILENTLY IN PRODUCTION.** `narrativeIsFallback`
   was `true` — the deterministic fallback sentence was used, not a real
   Gemini call. `GET /ai/provider` on the live backend reports
   `configured: true` (Render has *some* value in `GEMINI_API_KEY`), so the
   key itself is rejected/invalid, not simply absent. Separately: **local**
   `backend/.env`'s `GEMINI_API_KEY` is now blank (looks like a first step
   toward rotating the key that was pasted into a chat earlier — see the
   original note preserved below — already happened), but whatever value
   Render has was never updated to match and doesn't work either. **Action
   needed:** get a fresh Gemini key from aistudio.google.com/apikey and set
   it as `GEMINI_API_KEY` in Render's dashboard env vars (not just locally).
   This is a real product gap, not a crash — the fallback sentence is
   accurate and safe to send, just not the "AI-written note" the feature is
   meant to provide.
4. **WhatsApp send: NOT CONFIGURED, confirmed by a real attempt.** POST
   `.../send` returned `"Send failed: WhatsApp not configured yet."`
   Checked why: **every existing WhatsApp feature in this app
   (`routes/whatsappLink.js`, the 38 existing `communications` rows) sends
   via a `wa.me` click-to-chat link opened manually in the counselor's own
   WhatsApp app — never Meta's Cloud API.** `WHATSAPP_TOKEN`/
   `WHATSAPP_PHONE_NUMBER_ID` (the Cloud API credentials `sendWhatsAppImage`
   needs) have never actually been set up anywhere in this project. The
   original note below ("nothing new to configure beyond what the existing
   integration already needed") was **wrong** — this feature is the first
   thing that needs a real Meta WhatsApp Business Cloud API setup.
   **Action needed:** create a Meta Business/WhatsApp Cloud API app, get a
   permanent token + phone number ID, set both in Render's env vars, then
   re-test the send step specifically (steps 1–2 above don't need
   re-running).

**Original 2026-09-06 note on Gemini/WhatsApp (kept for the paper trail,
now superseded by the smoke test above):**
- Gemini key was pasted into a chat window earlier that session and should
  be treated as public — rotate it before relying on it for anything real.
- WhatsApp assumption ("nothing new to configure") — **disproven above.**

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
