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
