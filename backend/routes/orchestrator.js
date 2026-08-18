// Durable Orchestrator endpoints -- Leads Ecosystem redesign, Phase 4.
// Job visibility/approval/retry for a (future) Automation Center screen,
// plus the external-cron processing trigger. Nothing here touches the
// existing /automations routes (automation_rules / fireEvent) at all.

const express = require('express');
const db = require('../db');
const { processDueJobs, approveJob, retryDeadLetterJob } = require('../services/orchestrator');
const { runAutoModeAgents } = require('../services/agentScheduler');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /orchestrator/jobs?status=dead_letter — job list for a tenant,
// optionally filtered by status (pending/running/succeeded/failed/
// dead_letter/awaiting_approval/cancelled).
router.get('/jobs', async (req, res) => {
  const tid = tenantId(req);
  const { status } = req.query;
  const rows = status
    ? await db.prepare('SELECT * FROM automation_jobs WHERE tenant_id = ? AND status = ? ORDER BY created_at DESC LIMIT 200').all(tid, status)
    : await db.prepare('SELECT * FROM automation_jobs WHERE tenant_id = ? ORDER BY created_at DESC LIMIT 200').all(tid);
  res.json(rows);
});

// GET /orchestrator/jobs/:id
router.get('/jobs/:id', async (req, res) => {
  const tid = tenantId(req);
  const row = await db.prepare('SELECT * FROM automation_jobs WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!row) return res.status(404).json({ error: 'Job not found' });
  res.json(row);
});

// POST /orchestrator/jobs/:id/approve — a human approves a HIGH-risk job
// parked in awaiting_approval. Requires a valid auth token (this route
// is not in the public allowlist), so req.user is the approving human.
router.post('/jobs/:id/approve', async (req, res) => {
  const tid = tenantId(req);
  try {
    const job = await approveJob(tid, req.params.id, req.user?.id || req.body?.approved_by || null);
    res.json(job);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// POST /orchestrator/jobs/:id/retry — re-queue a dead-lettered job from scratch.
router.post('/jobs/:id/retry', async (req, res) => {
  const tid = tenantId(req);
  try {
    const job = await retryDeadLetterJob(tid, req.params.id);
    res.json(job);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// POST /orchestrator/process-due-jobs — called by an external cron
// (GitHub Actions, same reasoning and same x-cron-secret pattern as
// /whatsapp/process-scheduled: Render's free tier has no reliable
// background worker of its own). Processes ALL tenants' due jobs in one
// pass -- claimDueJobs() is tenant-agnostic on purpose, same as
// /whatsapp/process-scheduled, since a cron has no single tenant
// context.
router.post('/process-due-jobs', async (req, res) => {
  const expectedSecret = process.env.CRON_SECRET;
  if (expectedSecret && req.header('x-cron-secret') !== expectedSecret) {
    return res.status(401).json({ error: 'Invalid or missing cron secret' });
  }
  const limit = Number(req.query.limit) || 20;
  const result = await processDueJobs(limit);
  res.json(result);
});

// POST /orchestrator/run-auto-agents — external cron trigger for
// Phase 6's AUTO-mode scheduler (services/agentScheduler.js). Same
// x-cron-secret pattern as /orchestrator/process-due-jobs and
// /whatsapp/process-scheduled. A no-op in practice for any tenant that
// hasn't explicitly flipped automation_mode to 'auto' in Settings.
router.post('/run-auto-agents', async (req, res) => {
  const expectedSecret = process.env.CRON_SECRET;
  if (expectedSecret && req.header('x-cron-secret') !== expectedSecret) {
    return res.status(401).json({ error: 'Invalid or missing cron secret' });
  }
  const result = await runAutoModeAgents();
  res.json(result);
});

module.exports = router;
