// Registers the first tranche of Tool Registry tools -- thin wrappers
// around the already-real, already-working services identified in
// LEADS_AUTOMATION_AUDIT.md section 7 ("Reusable Services"). Called once
// from server.js at startup so every tool is registered before anything
// could invoke one.
//
// This is Tranche 1: communication, AI, and the lifecycle state machine
// added in Phase 2. Fee/document/admission tools are deliberately NOT
// included yet -- each will be added alongside the specific agent
// (Phase 5) that actually needs it, so a money-touching tool gets the
// same deliberate, individually-reviewed rollout as everything else
// instead of being wrapped in a batch nobody scrutinized closely.

const { randomUUID } = require('crypto');
const db = require('../db');
const { registerTool } = require('./toolRegistry');
const { sendWhatsAppMessage } = require('./whatsapp');
const { sendEmail } = require('./email');
const { generateText, generateJson } = require('./aiProvider');
const { createNotification } = require('../routes/notifications');
const { isValidTransition, computeAllowedNextStates, NEEDS_REVIEW } = require('./leadLifecycle');

function registerBuiltinTools() {
  registerTool({
    name: 'whatsapp.send_message',
    description: "Send a WhatsApp text message via the tenant's configured WhatsApp Business Cloud API. Real send -- throws if WhatsApp isn't configured, never silently no-ops.",
    riskTier: 'MEDIUM',
    inputSchema: {
      type: 'object',
      required: ['to_phone', 'text'],
      properties: { to_phone: { type: 'string' }, text: { type: 'string' } },
    },
    handler: async ({ to_phone, text }) => sendWhatsAppMessage(to_phone, text),
  });

  registerTool({
    name: 'email.send',
    description: "Send an email via the tenant's configured Brevo identity (their own account if set up, otherwise the platform default). Real send -- throws if not configured.",
    riskTier: 'MEDIUM',
    inputSchema: {
      type: 'object',
      required: ['to', 'subject', 'text'],
      properties: { to: { type: 'string' }, subject: { type: 'string' }, text: { type: 'string' } },
    },
    handler: async ({ to, subject, text }, context) => {
      const tenant = await db.prepare('SELECT * FROM tenants WHERE id = ?').get(context.tenant_id);
      return sendEmail(to, subject, text, tenant);
    },
  });

  registerTool({
    name: 'ai.generate_text',
    description: 'Generate free-form text from the configured AI provider (Claude/Gemini/OpenRouter). No side effect beyond the API call itself.',
    riskTier: 'LOW',
    inputSchema: {
      type: 'object',
      required: ['prompt'],
      properties: { prompt: { type: 'string' }, max_tokens: { type: 'number' } },
    },
    handler: async ({ prompt, max_tokens }) => generateText(prompt, max_tokens ? { maxTokens: max_tokens } : undefined),
  });

  registerTool({
    name: 'ai.generate_json',
    description: 'Generate a structured JSON response from the configured AI provider. No side effect beyond the API call itself.',
    riskTier: 'LOW',
    inputSchema: {
      type: 'object',
      required: ['prompt'],
      properties: { prompt: { type: 'string' }, max_tokens: { type: 'number' } },
    },
    handler: async ({ prompt, max_tokens }) => generateJson(prompt, max_tokens ? { maxTokens: max_tokens } : undefined),
  });

  registerTool({
    name: 'reminder.create',
    description: 'Create a follow-up reminder for a lead. Internal-only side effect -- no message is sent to the lead.',
    riskTier: 'LOW',
    inputSchema: {
      type: 'object',
      required: ['lead_id', 'title', 'due_at'],
      properties: {
        lead_id: { type: 'string' }, title: { type: 'string' }, due_at: { type: 'string' }, assigned_to: { type: 'string' },
      },
    },
    handler: async ({ lead_id, title, due_at, assigned_to }, context) => {
      const id = randomUUID();
      await db.prepare(`
        INSERT INTO reminders (id, tenant_id, lead_id, title, due_at, assigned_to)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(id, context.tenant_id, lead_id, title, due_at, assigned_to || null);
      return { id };
    },
  });

  registerTool({
    name: 'notification.create',
    description: "Create an in-app notification for the tenant's team. Internal-only side effect.",
    riskTier: 'LOW',
    inputSchema: {
      type: 'object',
      required: ['title'],
      properties: {
        title: { type: 'string' }, body: { type: 'string' }, link_type: { type: 'string' }, link_id: { type: 'string' },
      },
    },
    handler: async ({ title, body, link_type, link_id }, context) =>
      createNotification(context.tenant_id, { title, body: body || null, linkType: link_type || null, linkId: link_id || null }),
  });

  registerTool({
    name: 'lead.update_lifecycle_status',
    description: 'Move a lead to a new lifecycle_status if the transition is legal per the state machine (services/leadLifecycle.js). Records an entry in lead_lifecycle_transitions -- the same table and rules routes/leadLifecycle.js\'s PATCH endpoint uses.',
    riskTier: 'MEDIUM',
    inputSchema: {
      type: 'object',
      required: ['lead_id', 'to_status'],
      properties: { lead_id: { type: 'string' }, to_status: { type: 'string' }, reason: { type: 'string' } },
    },
    handler: async ({ lead_id, to_status, reason }, context) => {
      const lead = await db.prepare('SELECT id, lifecycle_status FROM leads WHERE tenant_id = ? AND id = ?').get(context.tenant_id, lead_id);
      if (!lead) throw new Error(`Lead ${lead_id} not found for this tenant`);

      const fromStatus = lead.lifecycle_status || NEEDS_REVIEW;
      if (!isValidTransition(fromStatus, to_status)) {
        throw new Error(
          `Cannot move lead ${lead_id} from ${fromStatus} to ${to_status}. ` +
          `Allowed: ${computeAllowedNextStates(fromStatus).join(', ') || '(none -- terminal state)'}`
        );
      }

      const transitionId = randomUUID();
      await db.transaction(async (tx) => {
        await tx.prepare("UPDATE leads SET lifecycle_status = ?, updated_at = datetime('now') WHERE tenant_id = ? AND id = ?")
          .run(to_status, context.tenant_id, lead_id);
        await tx.prepare(`
          INSERT INTO lead_lifecycle_transitions (id, tenant_id, lead_id, from_status, to_status, initiated_by, reason)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        `).run(transitionId, context.tenant_id, lead_id, fromStatus, to_status, context.actor.type, reason || null);
      });

      return { lead_id, from_status: fromStatus, to_status, transition_id: transitionId };
    },
  });
}

module.exports = { registerBuiltinTools };
