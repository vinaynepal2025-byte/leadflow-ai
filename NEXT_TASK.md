# NEXT_TASK.md — LeadFlow AI

What needs to happen next, and why. See `IMPLEMENTATION_PROGRESS.md` for what's
already done, `DECISION_LOG.md` for why things were sequenced the way they
were, `TECH_DEBT.md` for known issues not yet addressed.

---

## Top of list — `leads.assigned_to` is unpopulated in production

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
