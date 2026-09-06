# DECISION_LOG.md — LeadFlow AI

Records decisions made during development that aren't obvious from the code
itself — especially sequencing calls where the "correct" order wasn't
dictated purely by the Master Spec's own phase order. See
`IMPLEMENTATION_PROGRESS.md` for what was actually built/fixed as a result
of each decision.

---

## 2026-09-03 — Fix the 9 RLS-disabled tables before designing the full 54-table tenant-scoping policy set

**Decision:** when a live audit found the RLS picture split into two
buckets — 54 tables with RLS enabled but zero policies, and 9 tables with
RLS disabled entirely — fix the 9-table bucket immediately, as its own
small migration, rather than waiting to design and ship one comprehensive
tenant-scoping policy covering all 63 tables at once.

**Why:**
- **Exposure severity differs sharply between the two buckets.** The 54
  RLS-enabled-zero-policy tables were already effectively default-deny for
  `anon`/`authenticated` — Postgres denies all access on an RLS-enabled
  table with no matching policy. They were not the urgent gap. The 9
  RLS-disabled tables were the opposite: combined with Supabase's default
  full-CRUD grants to `anon`/`authenticated`, they were openly readable and
  writable by anyone holding the project's anon key, via PostgREST, with
  zero gating of any kind. That's a live, exploitable hole today; the other
  54 are a design gap for later.
- **Zero risk to existing backend behavior.** The backend connects as
  `postgres` (`rolbypassrls = true`, confirmed live), so enabling RLS and
  adding policies on these 9 tables cannot break any existing route,
  regardless of how the policy is worded — this made it a safe, isolated
  change to ship immediately rather than something that needed to wait for
  a broader review.
- **The full 54-table policy design is a bigger, slower piece of work.**
  It touches every core CRM table (`leads`, `users`, `communications`, etc.),
  needs a considered design for how `authenticated`-role access should
  actually work if/when this project adopts real per-user Supabase sessions
  (today's custom JWT auth doesn't reach the `authenticated` role at all —
  see `TECH_DEBT.md` §2 and `IMPLEMENTATION_PROGRESS.md`'s 2026-09-03
  entry), and deserves its own review rather than being rushed alongside
  an urgent fix.

**How to apply this going forward:** when a security audit surfaces
findings of different severity, ship the highest-severity, lowest-risk fix
immediately as its own migration rather than bundling it with a larger,
still-being-designed fix — don't let the bigger piece of work delay closing
an already-open, zero-cost-to-fix gap.

**Outcome:** see `IMPLEMENTATION_PROGRESS.md`'s 2026-09-03 entry — 9/9
tables fixed and live-verified. The 54-table policy design remains open,
tracked in `TECH_DEBT.md` §2.

---

## 2026-09-03 — Two-tier RLS model for the 54 remaining tables (owner/admin vs. per-employee)

**Decision:** rather than a flat tenant_id-only policy (the shape used for the
9-table fix), the 54 remaining tables use a two-tier model — `owner`/`admin`
get full tenant-wide access, every other role sees only rows connected to
them. Per Vinay's explicit requirement: "owner/admin sees all tenant data,
sub-employees only see their own assigned/created records."

**Why, and the per-group calls made to implement it:**

- **Group A (17 tables) — direct ownership column.** Where a table has an
  obvious owner (`assigned_to`, `created_by`, `recorded_by`, `uploaded_by`,
  etc.), the policy filters on that column directly. Two columns judged too
  weak to use this way: `lead_notes.author_name` (free text, not a user_id
  FK) and `capture_forms.assign_to` (a config value for future leads, not
  ownership of the form record itself) — both fell back to tenant-wide.
- **Group C/C2 (10 tables) — inherit ownership via `leads.assigned_to`.**
  Tables with no owner column of their own (`fee_payments`,
  `visa_applications`, `students`, etc.) but a `lead_id` inherit visibility
  from the lead's own `assigned_to`, via a 1-hop `EXISTS` join; two tables
  (`academic_risk_scores`, `payment_links`) need a 2-hop join (through
  `students`/`fee_payments` respectively) to reach `leads`. Reasoning: "own
  records" for a counselor means their whole caseload — the fee payments,
  visa applications, etc. for *their* leads — not just rows they personally
  clicked "create" on. `campaign_targets` and `alumni_availability` (no
  `tenant_id` column at all) got the same treatment via their own join
  chains.
- **`meetings` moved from Group A to Group D (tenant-wide) mid-design.**
  Its only candidate ownership column, `requested_by`, was judged too
  weak/inconsistently populated to safely filter per-employee access on —
  risking hiding real meetings from the counselor who should see them was
  worse than defaulting to visible-to-all. Revisit if a dedicated
  `assigned_to` column is ever added to this table.
- **Group D (21 tables) — tenant-wide for every role.** Tables with no
  ownership signal and no lead relation at all (`pipeline_stages`,
  `custom_field_definitions`, `whatsapp_templates`, the college directory,
  etc.) are genuinely tenant-level settings, not per-employee data — every
  employee in the tenant needs to read them regardless of role. `meetings`
  joined this group per the point above.
- **`users_safe` view for `password_hash` protection.** RLS policies filter
  rows, not columns, so a row-level "owner sees all users, employee sees
  self" policy on the `users` table directly would still let `admin` read
  every `password_hash` in the tenant via PostgREST once `authenticated`
  access is ever live. Instead, the base `users` table gets **no**
  authenticated policy at all (same backend-only treatment as `tenants`),
  and a `users_safe` view (owned by a BYPASSRLS role, so it can see all rows
  regardless of the base table's RLS, with the owner-sees-all/self-only
  logic embedded directly in its `WHERE` clause instead of a `CREATE POLICY`
  — Postgres has no policy mechanism for views) exposes every column except
  `password_hash`. Verified live: selecting `password_hash` from the view
  errors with "column does not exist," not just "access denied" — a
  structural guarantee, not a policy-dependent one.

**Outcome:** see `IMPLEMENTATION_PROGRESS.md`'s 2026-09-03 two-tier entry —
17/17 live-verified PASS, including a real write-and-rollback test proving
the join-chain filtering actually works (not just that it compiles). One
operational finding surfaced during verification and tracked separately in
`NEXT_TASK.md`: `leads.assigned_to` is NULL on all 785 production leads
today, so counselor-level visibility is currently a no-op in practice until
leads are actually assigned.

---

## 2026-09-06 — Exam Intelligence + Report Card System: port, not rebuild

**Decision:** the owner had this feature already built on a separate repo
(`nepalmedtech-vinay/nepalmbbs-website`) and asked for the same capability
inside leadflow-ai. Rather than adapting that implementation's code, it was
rebuilt against leadflow-ai's own already-existing (but unused)
`students`/`subjects`/`assessments`/`marks` schema and its own
Node/Postgres/Flutter stack, reusing that other implementation only for its
*lessons* (SQL-computed figures, blocked-not-guessed imports,
logged-not-overwritten corrections, guardian-phone discipline, grounded AI
narrative) — not its code, which was written for a completely different
architecture (a static Astro site, Deno edge functions, a hand-rolled
zero-dependency xlsx parser forced by that site's CSP).

**Why:** the two codebases share nothing at the infrastructure level.
leadflow-ai already has a real xlsx-reading dependency (`read-excel-file`),
a real image library (`sharp`), a real WhatsApp Cloud API integration
(`services/whatsapp.js`), and — critically — an existing CRM relationship
(`students.lead_id → leads`) that already carries `parent_name`/
`parent_phone`/`parent_relation`. Porting code written to route around a
different project's constraints would have meant reintroducing constraints
that don't exist here (e.g. a hand-written zero-dependency parser when a
real one is already a dependency) while missing the integration this
project actually has for free (guardian contact already lives in the CRM;
the other implementation had to invent that from scratch).

**Sheet-parsing redesign, mid-build, after inspecting a real file's
structure.** The first draft assumed a simple two-row format (a header row
plus a dedicated "MAX" row). The owner had a real college result sheet
(Chitwan Medical College, MBBS 1st year 2nd internal assessment) whose
*header structure only* was inspected (never student data, and that
inspection was discarded once done) and found genuinely different: a
merged multi-row header (a paper-group label spanning several subject
columns, readable back only via forward-fill once the merge is gone), a
max stated inline per subject (`ANA(20)`) rather than in a separate row,
one paper's subjects with no max at all, per-paper `Total`/`Result`
columns, and two columns both literally named "Cell Number". The parser
was rebuilt around this real shape rather than kept simple and wrong.
`Father's Name`/`Cell Number`/`Mother's Name` columns are recognized only
so they can be safely ignored — guardian contact comes from the CRM's own
`leads` record instead, not re-extracted from the sheet, which is the one
place this port is deliberately *simpler* than the reference
implementation (which had no CRM to draw that from).

**Assessment edits are guarded, mark edits are logged, subject-label edits
are free — three different rules for three different risk levels**, added
after the owner's explicit follow-up requirement that marks/subjects be
editable from the console, not just via re-import. A subject's name is a
label with no downstream meaning — free edit, no log. A mark's value
directly represents a fact already possibly shown/sent to a parent —
always logged to `mark_revisions` with a required reason, never a silent
UPDATE. An assessment's `max_marks`/`passing_marks` sit in between: free to
edit until a mark exists against it, then blocked (409) until the caller
passes `confirmed: true` + a reason — because changing a max after marks
exist against it silently changes every one of those marks' percentage
without changing a number in `marks` itself. Confirmed changes also reset
any not-yet-sent (`status = 'ready'`) report card in that exam_group back
to `'draft'`, so a stale percentage already computed under the old max can
never be sent as though nothing changed. A *sent* card is left alone —
it's a historical record of what was actually delivered, not something to
retroactively rewrite.

**Report templates are real per-tenant config, not a fixed layout, with a
lazy default rather than a migration-time seed.** `report_templates.config`
holds field selection/order, branding, footer/disclaimer. Rather than
looping over every current tenant at migration time to insert a default
row (fragile — a tenant created after the migration runs would get none),
`getOrCreateDefaultTemplate()` creates one on first use, per tenant. A
template a caller requests is shallow-merged over the default so an older
or partial template config still renders every section correctly instead
of a field silently going missing because a template predates it.

**A brand-new, independent top-level mobile section — not folded into
Leads.** First draft would have put an entry point somewhere inside the
Leads flow; the owner corrected this explicitly: Leads is prospect
follow-up, report cards are for already-enrolled students, and mixing the
two mental models in one screen/navigation path was rejected outright. The
fix was structural, not cosmetic — a new `exam_home_screen.dart` reachable
only from the More menu (matching how every other top-level section
already works, e.g. Parent CRM, Team, Colleges — see `more_screen.dart`'s
`kMoreMenuDefaults`), and confirming `lead_detail_screen.dart`/the leads
list were never touched. The database relationship
(`students.lead_id → leads`) stays exactly as designed — that's a
data-integrity link, not a UX one, and the owner was explicit that only
the *product surface* needed separating.

**`xlsx` (SheetJS) added as a devDependency, not a runtime one**, solely to
generate a synthetic test fixture reproducing the real sheet's structure
(fabricated data — see `backend/tests/lib/exam-sheet-fixture.js`). The
app's own import path is unchanged: still `read-excel-file`, matching
`routes/leadsImportExcel.js`'s existing convention. Adding a second reader
library at runtime would have been real, unjustified duplication; adding a
writer purely for tests is not the same thing.

**Nothing was applied to the live database, and no git commit was made** —
per explicit instruction, given this project's Supabase project also holds
785 real production leads. The migration and its RLS are both draft files,
reviewed against live schema via read-only `supabase-primary` calls but
never executed with `apply_migration`.
