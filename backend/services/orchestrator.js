// Durable Orchestrator -- Leads Ecosystem redesign, Phase 4. Per
// LEADS_AUTOMATION_AUDIT.md section 3: the existing automationEngine.js
// (`fireEvent()`) is synchronous and best-effort only -- no idempotency,
// no retry/backoff, no dead-letter state, no audit trail of executions.
// That file and its 4+ call sites (leads.js, documents.js, cockpit.js,
// leadAdsWebhook.js) are deliberately left untouched here -- this is a
// new, separate, parallel queue for the AI agent framework (Phase 5) to
// enqueue Tool Registry invocations into, not a rewrite of the existing
// automation-rules engine. Nothing about today's app changes.
//
// A job here is always "invoke this one registered tool with this
// input" -- enqueueJob() validates the tool exists via
// services/toolRegistry.js's getTool() before ever writing a row, so a
// typo'd tool name fails loudly at enqueue time, not silently at
// process time.

const { randomUUID } = require('crypto');
const db = require('../db');
const { getTool, invokeTool } = require('./toolRegistry');

const TERMINAL_STATUSES = new Set(['succeeded', 'dead_letter', 'cancelled']);
const DEFAULT_MAX_ATTEMPTS = 5;
const BASE_DELAY_SECONDS = 60;
const MAX_DELAY_SECONDS = 3600;

// Exponential backoff, capped at 1 hour: 60s, 120s, 240s, 480s, 960s, ...
// `attempts` is the number of attempts already made (so right after the
// 1st failure, attempts === 1).
function backoffSeconds(attempts) {
  return Math.min(BASE_DELAY_SECONDS * 2 ** Math.max(attempts - 1, 0), MAX_DELAY_SECONDS);
}

// context.approved (for the Tool Registry's HIGH-risk gate) comes from
// whether THIS job has been through approveJob() -- i.e. job.approved_at
// -- never from the job's current queue status, so a job re-run after
// approval still carries proof of that approval even though its status
// has already moved back to 'pending' by then.
function contextForJob(job) {
  return {
    tenant_id: job.tenant_id,
    actor: { type: job.initiated_by, id: job.initiated_by_id || undefined },
    approved: job.approved_at != null,
  };
}

// enqueueJob({ tenant_id, event?, tool_name, tool_input, idempotency_key?,
//              initiated_by?, initiated_by_id?, max_attempts?, requires_approval? })
//
// idempotency_key (when given) makes this durably safe to call twice for
// the same logical action (e.g. a webhook retry, a client double-submit)
// -- a second call with the same (tenant_id, idempotency_key) returns
// the existing job instead of creating a duplicate. Enforced by a real
// unique index (see the migration), not just an app-level check, so it
// holds even under concurrent enqueue attempts.
async function enqueueJob({
  tenant_id, event, tool_name, tool_input, idempotency_key,
  initiated_by, initiated_by_id, max_attempts, requires_approval,
}) {
  if (!tenant_id) throw new Error('enqueueJob: tenant_id is required');
  if (!tool_name) throw new Error('enqueueJob: tool_name is required');

  const tool = getTool(tool_name);
  if (!tool) throw new Error(`enqueueJob: unknown tool "${tool_name}". Call listTools() (GET /tools) to see what's registered.`);

  if (idempotency_key) {
    const existing = await db.prepare(
      'SELECT * FROM automation_jobs WHERE tenant_id = ? AND idempotency_key = ?'
    ).get(tenant_id, idempotency_key);
    if (existing) return existing;
  }

  const initiator = initiated_by || 'automation';
  // Mirrors the Tool Registry's own HIGH-risk gate so a caller doesn't
  // have to duplicate that risk-tier logic: a HIGH tool enqueued by
  // anything other than a human starts life parked for approval instead
  // of burning retry attempts failing the same gate repeatedly.
  const needsApproval = requires_approval !== undefined
    ? requires_approval
    : (tool.riskTier === 'HIGH' && initiator !== 'manual');

  const id = randomUUID();
  const status = needsApproval ? 'awaiting_approval' : 'pending';

  try {
    await db.prepare(`
      INSERT INTO automation_jobs
        (id, tenant_id, event, tool_name, tool_input_json, idempotency_key, initiated_by, initiated_by_id, status, max_attempts, requires_approval)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      id, tenant_id, event || null, tool_name, JSON.stringify(tool_input || {}), idempotency_key || null,
      initiator, initiated_by_id || null, status, max_attempts || DEFAULT_MAX_ATTEMPTS, needsApproval
    );
  } catch (err) {
    // A concurrent enqueue with the same idempotency_key won the race
    // between our check above and this insert -- that's the durable
    // dedupe guarantee working as intended, not a real failure. Return
    // whichever row actually landed instead of throwing.
    if (idempotency_key && /duplicate key|unique constraint/i.test(err.message)) {
      const existing = await db.prepare('SELECT * FROM automation_jobs WHERE tenant_id = ? AND idempotency_key = ?').get(tenant_id, idempotency_key);
      if (existing) return existing;
    }
    throw err;
  }

  return db.prepare('SELECT * FROM automation_jobs WHERE id = ?').get(id);
}

// Atomically claims up to `limit` due jobs by moving them to 'running'
// in one statement (SELECT ... FOR UPDATE SKIP LOCKED inside the UPDATE
// target), so two overlapping calls to processDueJobs (e.g. the cron and
// a manual "process now" click) never claim the same job twice. Standard
// Postgres job-queue idiom -- its correctness rests on being
// well-established syntax, not something novel; this sandbox has no live
// Postgres to execute it against directly (verified against production
// once merged and deployed, same as every other migration this session).
async function claimDueJobs(limit = 20) {
  return db.prepare(`
    UPDATE automation_jobs
    SET status = 'running', updated_at = datetime('now')
    WHERE id IN (
      SELECT id FROM automation_jobs
      WHERE status = 'pending' AND next_attempt_at <= now()
      ORDER BY next_attempt_at ASC
      LIMIT ?
      FOR UPDATE SKIP LOCKED
    )
    RETURNING *
  `).all(limit);
}

async function runJob(job) {
  const toolInput = JSON.parse(job.tool_input_json || '{}');
  const context = contextForJob(job);

  try {
    const result = await invokeTool(job.tool_name, toolInput, context);
    await db.prepare(
      "UPDATE automation_jobs SET status = 'succeeded', result_json = ?, updated_at = datetime('now') WHERE id = ?"
    ).run(JSON.stringify(result ?? null).slice(0, 4000), job.id);
    return { id: job.id, status: 'succeeded' };
  } catch (err) {
    // A HIGH-risk tool rejected for lack of approval is not transient --
    // retrying identically will just fail identically every time. Park
    // it for a human via approveJob() instead of burning attempts.
    if (!context.approved && /HIGH risk/.test(err.message)) {
      await db.prepare(
        "UPDATE automation_jobs SET status = 'awaiting_approval', last_error = ?, updated_at = datetime('now') WHERE id = ?"
      ).run(err.message, job.id);
      return { id: job.id, status: 'awaiting_approval' };
    }

    const attempts = job.attempts + 1;
    if (attempts >= job.max_attempts) {
      await db.prepare(
        "UPDATE automation_jobs SET status = 'dead_letter', attempts = ?, last_error = ?, updated_at = datetime('now') WHERE id = ?"
      ).run(attempts, err.message, job.id);
      return { id: job.id, status: 'dead_letter' };
    }

    const delaySeconds = backoffSeconds(attempts);
    await db.prepare(`
      UPDATE automation_jobs
      SET status = 'pending', attempts = ?, last_error = ?,
          next_attempt_at = now() + (? || ' seconds')::interval, updated_at = datetime('now')
      WHERE id = ?
    `).run(attempts, err.message, String(delaySeconds), job.id);
    return { id: job.id, status: 'pending', retry_in_seconds: delaySeconds };
  }
}

async function processDueJobs(limit = 20) {
  const jobs = await claimDueJobs(limit);
  const results = [];
  for (const job of jobs) {
    results.push(await runJob(job));
  }
  return { claimed: jobs.length, results };
}

// A human approves a job parked in 'awaiting_approval'. Re-queues it as
// 'pending' with approved_at set, so the next processDueJobs pass picks
// it back up -- and contextForJob() will now report approved: true for
// it, satisfying the Tool Registry's HIGH-risk gate.
async function approveJob(tenantId, jobId, approvedByUserId) {
  const job = await db.prepare('SELECT * FROM automation_jobs WHERE tenant_id = ? AND id = ?').get(tenantId, jobId);
  if (!job) throw new Error('Job not found');
  if (job.status !== 'awaiting_approval') throw new Error(`Job is not awaiting approval (status: ${job.status})`);

  await db.prepare(`
    UPDATE automation_jobs
    SET status = 'pending', approved_by = ?, approved_at = datetime('now'), next_attempt_at = now(), updated_at = datetime('now')
    WHERE id = ?
  `).run(approvedByUserId || null, jobId);
  return db.prepare('SELECT * FROM automation_jobs WHERE id = ?').get(jobId);
}

// Re-queues a dead-lettered job from scratch (attempts reset to 0) --
// e.g. once whatever external issue caused every attempt to fail
// (WhatsApp misconfigured, AI provider down) has been fixed.
async function retryDeadLetterJob(tenantId, jobId) {
  const job = await db.prepare('SELECT * FROM automation_jobs WHERE tenant_id = ? AND id = ?').get(tenantId, jobId);
  if (!job) throw new Error('Job not found');
  if (job.status !== 'dead_letter') throw new Error(`Job is not dead-lettered (status: ${job.status})`);

  await db.prepare(`
    UPDATE automation_jobs SET status = 'pending', attempts = 0, last_error = NULL, next_attempt_at = now(), updated_at = datetime('now')
    WHERE id = ?
  `).run(jobId);
  return db.prepare('SELECT * FROM automation_jobs WHERE id = ?').get(jobId);
}

module.exports = {
  enqueueJob, claimDueJobs, runJob, processDueJobs, approveJob, retryDeadLetterJob,
  backoffSeconds, contextForJob, TERMINAL_STATUSES, DEFAULT_MAX_ATTEMPTS,
};
