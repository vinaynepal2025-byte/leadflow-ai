// Document Agent -- Leads Ecosystem redesign, Phase 5, tranche 2.
//
// Scope: notice which of a lead's documents are missing, pending, or
// rejected, and flag it for follow-up. Built on documents.js's own
// status model (pending/verified/rejected) plus, when the lead has a
// visa application on file, the same deterministic checklist
// cross-reference journey.js's GET /visa/:id/checklist already computes
// (LEADS_AUTOMATION_AUDIT.md section 10 names this exact checklist logic
// as "already exactly the kind of check a Document Agent needs to run").
// The checklist matching is re-implemented here as a small, self-
// contained, read-only query rather than importing journey.js's route
// internals -- routes aren't meant to be required as libraries.
//
// Explicitly out of scope: this agent never verifies or rejects a
// document itself (that stays a human judgment call via documents.js's
// existing PATCH), and never advances a lead's lifecycle_status on its
// own -- it only ever recommends a reminder.

const db = require('../../db');
const { enqueueAgentAction } = require('./agentKit');

const AGENT_NAME = 'document';

async function analyze(tenantId, leadId) {
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tenantId, leadId);
  if (!lead) throw new Error(`Lead ${leadId} not found for this tenant`);

  const documents = await db.prepare(
    'SELECT doc_type, status FROM documents WHERE tenant_id = ? AND lead_id = ?'
  ).all(tenantId, leadId);

  const pendingOrRejected = documents.filter((d) => d.status === 'pending' || d.status === 'rejected');

  // If the lead has an active (non-terminal) visa application, cross-
  // reference the tenant's checklist for that country/visa_type against
  // documents actually on file -- catches doc_types the lead hasn't
  // uploaded at all, which pendingOrRejected alone can't see.
  const visa = await db.prepare(
    "SELECT * FROM visa_applications WHERE tenant_id = ? AND lead_id = ? AND status NOT IN ('Approved','Rejected') ORDER BY created_at DESC LIMIT 1"
  ).get(tenantId, leadId);

  let missingFromChecklist = [];
  if (visa) {
    const required = await db.prepare(
      'SELECT doc_type FROM visa_checklist_items WHERE tenant_id = ? AND country = ? AND visa_type = ?'
    ).all(tenantId, visa.country, visa.visa_type);
    const onFile = new Set(documents.map((d) => d.doc_type.trim().toLowerCase()));
    missingFromChecklist = required
      .map((r) => r.doc_type)
      .filter((docType) => !onFile.has(docType.trim().toLowerCase()));
  }

  const issueCount = pendingOrRejected.length + missingFromChecklist.length;
  const situation = issueCount > 0 ? 'documents_incomplete' : 'documents_complete';

  let recommendedAction = null;
  if (issueCount > 0) {
    const parts = [];
    if (pendingOrRejected.length > 0) {
      const rejected = pendingOrRejected.filter((d) => d.status === 'rejected').length;
      const pending = pendingOrRejected.length - rejected;
      if (rejected > 0) parts.push(`${rejected} rejected`);
      if (pending > 0) parts.push(`${pending} pending review`);
    }
    if (missingFromChecklist.length > 0) parts.push(`${missingFromChecklist.length} not yet uploaded (${missingFromChecklist.join(', ')})`);

    recommendedAction = {
      tool_name: 'reminder.create',
      tool_input: {
        lead_id: leadId,
        title: `Documents need attention for ${lead.full_name}: ${parts.join('; ')}`,
        due_at: new Date().toISOString(),
      },
    };
  }

  return {
    agent: AGENT_NAME,
    lead_id: leadId,
    documents_on_file: documents.length,
    pending_or_rejected: pendingOrRejected,
    visa_checklist_checked: Boolean(visa),
    missing_from_checklist: missingFromChecklist,
    situation,
    recommended_action: recommendedAction,
  };
}

// See agentKit.js's header comment -- act() only runs today from an
// authenticated human action (routes/agents.js passes
// initiatedBy: 'manual').
async function act(tenantId, leadId, { initiatedBy = 'manual', initiatedById } = {}) {
  const result = await analyze(tenantId, leadId);
  if (!result.recommended_action) {
    return { enqueued: false, reason: 'This lead has no outstanding document issues.', analysis: result };
  }
  const job = await enqueueAgentAction({
    tenantId,
    agentName: AGENT_NAME,
    leadId,
    toolName: result.recommended_action.tool_name,
    toolInput: result.recommended_action.tool_input,
    initiatedBy,
    initiatedById,
  });
  return { enqueued: true, job, analysis: result };
}

module.exports = { AGENT_NAME, analyze, act };
