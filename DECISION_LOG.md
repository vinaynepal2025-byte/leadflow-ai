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
