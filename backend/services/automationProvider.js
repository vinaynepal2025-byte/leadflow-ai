// AutomationProvider -- Leads Ecosystem redesign, Phase 7 (future n8n
// compatibility layer). This is the pluggable interface the spec asked
// for: LocalAutomationEngine (the ONLY provider actually running
// anywhere in this codebase) wraps Phase 3/4's already-real Tool
// Registry + durable orchestrator; N8nAutomationEngine exists purely as
// a contract-shaped stub proving the interface is genuinely
// implementation-agnostic.
//
// Per the spec, verbatim: "DO NOT TURN LEADFLOW INTO AN n8n WRAPPER...
// n8n must remain a future interchangeable automation execution
// provider... The application must work fully without n8n today." It
// does -- nothing in server.js, any route, or any agent imports or
// instantiates N8nAutomationEngine. getAutomationProvider() below always
// returns LocalAutomationEngine; there is no env var, config flag, or
// code path anywhere that can select the other one. That absence is
// deliberate, not an oversight -- see
// docs/N8N_AUTOMATION_PROVIDER_CONTRACT.md for the full design and what
// a real future integration would still need to add.

/**
 * @typedef {Object} AutomationJobRequest
 * @property {string} tenant_id
 * @property {string} [event] -- the domain event this job is fulfilling, e.g. 'agent.follow_up' or 'lead.stage_changed'. Informational/audit only.
 * @property {string} tool_name -- must be a name registered in services/toolRegistry.js.
 * @property {Object} tool_input
 * @property {string} [idempotency_key] -- durable dedupe key, unique per (tenant_id, idempotency_key).
 * @property {'manual'|'ai'|'automation'|'system'} initiated_by
 * @property {string} [initiated_by_id]
 * @property {number} [max_attempts]
 * @property {string} [correlation_id] -- ties a chain of related jobs together across one logical workflow run (e.g. every job an n8n execution spawns). Part of the contract every provider must accept even though LocalAutomationEngine doesn't yet have a structured logger to actually make use of it (see LEADS_AUTOMATION_AUDIT.md section 8) -- so a future N8nAutomationEngine can propagate its own execution ID through this field without the interface itself changing.
 */

/** Abstract base -- every method throws by design; a real provider must override all of them. */
class AutomationProvider {
  get name() { throw new Error('AutomationProvider.name must be implemented by a subclass'); }
  /** @param {AutomationJobRequest} request @returns {Promise<Object>} the created/existing job row */
  async enqueueJob(request) { throw new Error(`${this.constructor.name}.enqueueJob is not implemented`); }
  async getJob(tenantId, jobId) { throw new Error(`${this.constructor.name}.getJob is not implemented`); }
  async listJobs(tenantId, filters) { throw new Error(`${this.constructor.name}.listJobs is not implemented`); }
  async approveJob(tenantId, jobId, approvedByUserId) { throw new Error(`${this.constructor.name}.approveJob is not implemented`); }
  async retryJob(tenantId, jobId) { throw new Error(`${this.constructor.name}.retryJob is not implemented`); }
  /** Drains currently-due work. Called by this provider's own scheduler/cron -- LocalAutomationEngine's is the existing POST /orchestrator/process-due-jobs. */
  async processDueWork(limit) { throw new Error(`${this.constructor.name}.processDueWork is not implemented`); }
}

// The only provider that actually runs. Every method is a thin,
// same-shape wrapper around services/orchestrator.js -- no new logic,
// no new database access, just the interface Phase 7's future swap
// would need.
class LocalAutomationEngine extends AutomationProvider {
  get name() { return 'local'; }

  async enqueueJob(request) {
    const { enqueueJob } = require('./orchestrator');
    return enqueueJob({
      tenant_id: request.tenant_id,
      event: request.event,
      tool_name: request.tool_name,
      tool_input: request.tool_input,
      idempotency_key: request.idempotency_key,
      initiated_by: request.initiated_by,
      initiated_by_id: request.initiated_by_id,
      max_attempts: request.max_attempts,
    });
  }

  async getJob(tenantId, jobId) {
    const db = require('../db');
    return db.prepare('SELECT * FROM automation_jobs WHERE tenant_id = ? AND id = ?').get(tenantId, jobId);
  }

  async listJobs(tenantId, filters = {}) {
    const db = require('../db');
    return filters.status
      ? db.prepare('SELECT * FROM automation_jobs WHERE tenant_id = ? AND status = ? ORDER BY created_at DESC LIMIT 200').all(tenantId, filters.status)
      : db.prepare('SELECT * FROM automation_jobs WHERE tenant_id = ? ORDER BY created_at DESC LIMIT 200').all(tenantId);
  }

  async approveJob(tenantId, jobId, approvedByUserId) {
    const { approveJob } = require('./orchestrator');
    return approveJob(tenantId, jobId, approvedByUserId);
  }

  async retryJob(tenantId, jobId) {
    const { retryDeadLetterJob } = require('./orchestrator');
    return retryDeadLetterJob(tenantId, jobId);
  }

  async processDueWork(limit) {
    const { processDueJobs } = require('./orchestrator');
    return processDueJobs(limit);
  }
}

// Contract-shaped stub ONLY -- see the file header. Never imported by
// server.js, any route, or getAutomationProvider() below. Constructing
// it is harmless (it just stores config); calling any method throws
// immediately and explicitly, so it cannot silently pretend to do
// something it doesn't.
class N8nAutomationEngine extends AutomationProvider {
  get name() { return 'n8n'; }

  /**
   * @param {Object} config
   * @param {string} config.webhookBaseUrl -- where LeadFlow would POST a job for n8n to execute.
   * @param {string} config.signingSecret -- HMAC secret for signing outbound requests and verifying n8n's callback, same X-Hub-Signature-256-style pattern services/webhookSecurity.js already established for Meta webhooks.
   * @param {string} [config.apiKey] -- for calling n8n's own REST API (workflow status lookups), if needed.
   */
  constructor(config) {
    super();
    this.config = config; // stored only -- never read from process.env anywhere in this codebase today.
  }

  _notImplemented(method) {
    throw new Error(
      `N8nAutomationEngine.${method} is a future-phase contract stub, not a working integration. ` +
      'See docs/N8N_AUTOMATION_PROVIDER_CONTRACT.md for what a real implementation would need.'
    );
  }

  async enqueueJob() { this._notImplemented('enqueueJob'); }
  async getJob() { this._notImplemented('getJob'); }
  async listJobs() { this._notImplemented('listJobs'); }
  async approveJob() { this._notImplemented('approveJob'); }
  async retryJob() { this._notImplemented('retryJob'); }
  async processDueWork() { this._notImplemented('processDueWork'); }
}

// The entire "turn on n8n" switch a real future phase would flip is
// changing this one function -- deliberately not present yet. No env
// var, no tenant setting, no code path anywhere else in this app can
// select N8nAutomationEngine.
function getAutomationProvider() {
  return new LocalAutomationEngine();
}

module.exports = { AutomationProvider, LocalAutomationEngine, N8nAutomationEngine, getAutomationProvider };
