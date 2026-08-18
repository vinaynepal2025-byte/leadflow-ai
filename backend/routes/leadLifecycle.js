// Lead Lifecycle state machine endpoints -- Leads Ecosystem redesign,
// Phase 2 (Domain Model). Deliberately a new, separate route file/prefix
// (PATCH /leads/:id/lifecycle-status) rather than folding this into
// leads.js's existing PATCH /:id -- that handler's `stage` field is left
// completely untouched so nothing about today's mobile app breaks; this
// is purely additive.

const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { fireEvent } = require('../services/automationEngine');
const { isValidTransition, computeAllowedNextStates, NEEDS_REVIEW } = require('../services/leadLifecycle');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /leads/:id/lifecycle-status — current status + legal next moves.
// The Automation Center / agent framework (later phases) and any mobile
// UI both need "what can this lead legally become next" without
// duplicating the state machine's rules client-side.
router.get('/:id/lifecycle-status', async (req, res) => {
  const tid = tenantId(req);
  const lead = await db.prepare('SELECT id, lifecycle_status FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const current = lead.lifecycle_status || NEEDS_REVIEW;
  res.json({
    lead_id: lead.id,
    lifecycle_status: current,
    allowed_next: computeAllowedNextStates(current),
  });
});

// GET /leads/:id/lifecycle-history — the transition audit trail.
router.get('/:id/lifecycle-history', async (req, res) => {
  const tid = tenantId(req);
  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const rows = await db.prepare(
    'SELECT * FROM lead_lifecycle_transitions WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC'
  ).all(tid, req.params.id);
  res.json(rows);
});

// PATCH /leads/:id/lifecycle-status  { to_status, initiated_by?, reason? }
// initiated_by defaults to 'manual' -- a human made this move via the
// app. Automation/agent code (later phases) will pass 'automation'/'ai'
// explicitly once they exist; nothing does yet, so every real transition
// through this endpoint today is genuinely manual, not a placeholder.
router.patch('/:id/lifecycle-status', async (req, res) => {
  const tid = tenantId(req);
  const { to_status, reason } = req.body;
  const validInitiators = ['manual', 'ai', 'automation', 'system'];
  const initiatedBy = validInitiators.includes(req.body.initiated_by) ? req.body.initiated_by : 'manual';

  if (!to_status) return res.status(400).json({ error: 'to_status is required' });

  const lead = await db.prepare('SELECT id, lifecycle_status FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const fromStatus = lead.lifecycle_status || NEEDS_REVIEW;
  if (!isValidTransition(fromStatus, to_status)) {
    return res.status(422).json({
      error: `Cannot move a lead from ${fromStatus} to ${to_status}.`,
      lifecycle_status: fromStatus,
      allowed_next: computeAllowedNextStates(fromStatus),
    });
  }

  const transitionId = randomUUID();
  await db.transaction(async (tx) => {
    await tx.prepare(
      "UPDATE leads SET lifecycle_status = ?, updated_at = datetime('now') WHERE tenant_id = ? AND id = ?"
    ).run(to_status, tid, req.params.id);
    await tx.prepare(`
      INSERT INTO lead_lifecycle_transitions (id, tenant_id, lead_id, from_status, to_status, initiated_by, reason)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(transitionId, tid, req.params.id, fromStatus, to_status, initiatedBy, reason || null);
  });

  // Fire-and-forget, same pattern as every other trigger call site
  // (leads.js, documents.js, cockpit.js) -- the transition itself is
  // already committed above, so a failing automation rule must never
  // undo or block it.
  fireEvent('lead.lifecycle_status_changed', {
    tenant_id: tid,
    lead_id: req.params.id,
    from_status: fromStatus,
    to_status,
    initiated_by: initiatedBy,
  }).catch((err) => console.error('lead.lifecycle_status_changed automation failed (transition already saved):', err.message));

  const updated = await db.prepare('SELECT * FROM leads WHERE id = ?').get(req.params.id);
  res.json({
    ...updated,
    custom_fields: updated.custom_fields ? JSON.parse(updated.custom_fields) : {},
    lifecycle_transition_id: transitionId,
  });
});

module.exports = router;
