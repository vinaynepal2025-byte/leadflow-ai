// AUTO-mode agent scheduler -- Leads Ecosystem redesign, Phase 6
// (MANUAL/AUTO mode). Every tenant defaults to MANUAL (see the
// automation_mode migration) -- nothing here runs against any tenant's
// leads until that tenant's admin explicitly flips the toggle in
// Settings. This is the one piece of the whole redesign that can act on
// real leads without a human clicking a button per action, so it is
// deliberately the most conservative-by-default part of the system.
//
// What "running an agent" actually does here is call the SAME act()
// every agent already exposes to routes/agents.js's human-triggered
// path -- the only difference is initiated_by: 'ai' instead of
// 'manual'. act() only ever ENQUEUES a job via the durable orchestrator
// (Phase 4); it does not execute anything itself. Execution happens a
// few minutes later when the orchestrator's own existing cron
// (POST /orchestrator/process-due-jobs) claims and runs the job -- this
// scheduler adds no new execution engine, just a new way jobs get
// enqueued. Every agent's own idempotency_key (agentKit.js) already
// caps how often the same lead+agent+action can be enqueued, so running
// this scan on a tight cadence is redundant-but-harmless, not spammy.
//
// Bounded on purpose: at most MAX_LEADS_PER_TENANT leads per tenant per
// run, oldest-updated-first, so coverage rotates across a tenant's whole
// lead base over successive runs instead of hammering the same leads
// (or one huge tenant) every single tick.

const db = require('../db');
const { AGENTS } = require('./agents/registry');

const MAX_LEADS_PER_TENANT = 50;

async function runAutoModeAgents({ maxLeadsPerTenant = MAX_LEADS_PER_TENANT } = {}) {
  const autoTenants = await db.prepare(
    "SELECT id FROM tenants WHERE automation_mode = 'auto'"
  ).all();

  const tenantResults = [];
  for (const tenant of autoTenants) {
    const leads = await db.prepare(
      'SELECT id FROM leads WHERE tenant_id = ? AND deleted_at IS NULL ORDER BY updated_at ASC NULLS FIRST LIMIT ?'
    ).all(tenant.id, maxLeadsPerTenant);

    let actionsEnqueued = 0;
    const errors = [];

    for (const lead of leads) {
      for (const [agentName, agent] of Object.entries(AGENTS)) {
        try {
          const result = await agent.act(tenant.id, lead.id, { initiatedBy: 'ai', initiatedById: `scheduler:${agentName}` });
          if (result.enqueued) actionsEnqueued += 1;
        } catch (err) {
          // One agent failing on one lead (e.g. a transient DB hiccup)
          // must never stop the scan for the rest of the tenant's leads.
          errors.push({ lead_id: lead.id, agent: agentName, error: err.message });
        }
      }
    }

    tenantResults.push({
      tenant_id: tenant.id,
      leads_scanned: leads.length,
      actions_enqueued: actionsEnqueued,
      error_count: errors.length,
      errors: errors.slice(0, 20), // cap the response size, not the actual error handling
    });
  }

  return { tenants_processed: tenantResults.length, results: tenantResults };
}

module.exports = { runAutoModeAgents, MAX_LEADS_PER_TENANT };
