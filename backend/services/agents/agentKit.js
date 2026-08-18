// Shared helpers for the Leads Ecosystem AI agents (Phase 5). Small and
// deliberately thin -- each agent still owns its own domain logic; this
// only factors out the two things every agent genuinely needs the same
// way: calling AI without ever fabricating an answer if it fails, and
// proposing/enqueuing an action through the Tool Registry + Orchestrator
// (Phase 3/4) rather than touching the database directly.
//
// Design rule this session settled on for Tranche 1: an agent's
// analyze() is ALWAYS read-only (no side effects, nothing enqueued). A
// separate act() must be explicitly called to actually enqueue the
// recommended action -- and right now, the only thing that calls act()
// is a human clicking a button behind an authenticated route (see
// routes/agents.js), which passes initiated_by: 'manual'. Nothing in
// this codebase invokes act() autonomously yet -- that's the Manual/Auto
// mode toggle (Phase 6), which doesn't exist yet. This keeps every agent
// safely recommendation-only today while leaving act() ready for Phase 6
// to call with initiated_by: 'ai' once autonomous mode is a real,
// deliberately-chosen tenant setting rather than an implicit default.

const { generateJson } = require('../aiProvider');
const { enqueueJob } = require('../orchestrator');

// Never throws -- returns null on any failure (no key configured, the
// provider is down, malformed JSON back) so a caller can fall back to
// pure deterministic reasoning instead of fabricating a narrative. Same
// posture as services/smartTriage.js: escalate/degrade, never guess.
async function safeAiJson(prompt, options) {
  try {
    return await generateJson(prompt, options);
  } catch (err) {
    console.warn(`[agentKit] AI call failed, falling back to deterministic-only output: ${err.message}`);
    return null;
  }
}

// Enqueues an agent's recommended action through the durable orchestrator
// (Phase 4), which itself routes through the Tool Registry (Phase 3) --
// an agent never calls a service or touches the database directly.
// idempotency_key defaults to one-per-lead-per-agent-per-day, so a
// repeated analyze()+act() cycle (e.g. a human clicking the button twice,
// or a future scheduler re-running the same day) can't spam duplicate
// actions onto the same lead.
async function enqueueAgentAction({
  tenantId, agentName, leadId, toolName, toolInput, initiatedBy = 'ai', initiatedById, dedupeSuffix, maxAttempts,
}) {
  const suffix = dedupeSuffix || new Date().toISOString().slice(0, 10);
  return enqueueJob({
    tenant_id: tenantId,
    event: `agent.${agentName}`,
    tool_name: toolName,
    tool_input: toolInput,
    idempotency_key: `agent:${agentName}:${leadId}:${toolName}:${suffix}`,
    initiated_by: initiatedBy,
    initiated_by_id: initiatedById || agentName,
    max_attempts: maxAttempts,
  });
}

module.exports = { safeAiJson, enqueueAgentAction };
