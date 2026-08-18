// Payment/Commitment Agent -- Leads Ecosystem redesign, Phase 5,
// tranche 3.
//
// Scope: notice a fee_payments installment that's now overdue and flag
// it. fees.js already does the deterministic part right at creation
// time -- reminderForFee() schedules a reminder for the due date, and
// generateReceipt()/the paid notification fire automatically the moment
// a fee is marked paid (LEADS_AUTOMATION_AUDIT.md section 10: "already
// fully automatic today; formalizing them as agent actions with an audit
// trail is mostly a wrapping exercise"). The real gap this agent fills
// is what happens AFTER that first reminder passes unpaid: fees.js has
// no escalation once a fee is actually overdue, and this agent does --
// deduped per fee_id so it won't re-nag on every run once already
// flagged today.
//
// Explicitly out of scope: never marks a fee paid, never touches money
// or a payment gateway (that stays the tenant's own configured Razorpay/
// eSewa/Khalti integration via fees.js/payments.js), never changes
// lifecycle_status. Only ever recommends reminder.create.

const db = require('../../db');
const { enqueueAgentAction } = require('./agentKit');

const AGENT_NAME = 'payment_commitment';

async function analyze(tenantId, leadId) {
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tenantId, leadId);
  if (!lead) throw new Error(`Lead ${leadId} not found for this tenant`);

  const fees = await db.prepare(
    "SELECT * FROM fee_payments WHERE tenant_id = ? AND lead_id = ? AND status IN ('pending', 'overdue') ORDER BY due_date ASC"
  ).all(tenantId, leadId);

  const today = new Date().toISOString().slice(0, 10);
  const overdueFees = fees.filter((f) => f.due_date && f.due_date < today);

  let situation = 'no_action_needed';
  let recommendedAction = null;
  let dedupeSuffix;

  if (overdueFees.length > 0) {
    situation = 'payment_overdue';
    const totalOverdue = overdueFees.reduce((sum, f) => sum + Number(f.amount || 0), 0);
    const oldest = overdueFees[0];
    dedupeSuffix = `overdue-${oldest.id}`; // one reminder per overdue installment, not one per run
    recommendedAction = {
      tool_name: 'reminder.create',
      tool_input: {
        lead_id: leadId,
        title: `Overdue payment: ${lead.full_name} — ₹${totalOverdue} across ${overdueFees.length} installment(s), oldest due ${oldest.due_date}`,
        due_at: new Date().toISOString(),
      },
    };
  } else if (fees.length > 0) {
    situation = 'payment_pending_not_yet_due';
  }

  return {
    agent: AGENT_NAME,
    lead_id: leadId,
    pending_or_overdue_count: fees.length,
    overdue_count: overdueFees.length,
    overdue_total: overdueFees.reduce((sum, f) => sum + Number(f.amount || 0), 0),
    situation,
    recommended_action: recommendedAction,
    _dedupe_suffix: dedupeSuffix,
  };
}

// See agentKit.js's header comment -- act() only runs today from an
// authenticated human action (routes/agents.js passes
// initiatedBy: 'manual'). dedupeSuffix keys off the specific overdue
// fee_id, so a human clicking act() again after the same fee is still
// overdue reuses the same job instead of creating a duplicate reminder
// every time.
async function act(tenantId, leadId, { initiatedBy = 'manual', initiatedById } = {}) {
  const result = await analyze(tenantId, leadId);
  if (!result.recommended_action) {
    return { enqueued: false, reason: `No overdue payment action needed (${result.situation}).`, analysis: result };
  }
  const job = await enqueueAgentAction({
    tenantId,
    agentName: AGENT_NAME,
    leadId,
    toolName: result.recommended_action.tool_name,
    toolInput: result.recommended_action.tool_input,
    initiatedBy,
    initiatedById,
    dedupeSuffix: result._dedupe_suffix,
  });
  return { enqueued: true, job, analysis: result };
}

module.exports = { AGENT_NAME, analyze, act };
