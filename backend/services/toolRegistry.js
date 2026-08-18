// Tool Registry -- Leads Ecosystem redesign, Phase 3. Per
// LEADS_AUTOMATION_AUDIT.md section 8: nothing in the codebase today
// treats "send a WhatsApp message" or "create a fee reminder" as a
// discrete, permissioned, schema-validated *tool* -- they're just plain
// function calls. This registry is that missing interposition layer:
// every capability the AI agent framework (later phases) will be
// allowed to invoke is registered here with an input schema, a risk
// tier, and unconditional audit logging -- and it wraps the SAME real,
// already-working service functions from services/whatsapp.js,
// services/email.js, services/aiProvider.js, etc. (per the audit's
// section 7 "reusable services" list) rather than reimplementing them.
//
// Nothing here deletes, replaces, or is required by any existing route
// -- ai.js, cockpit.js, whatsapp.js's own routes, etc. keep calling
// their services directly exactly as before. This is a new, additive,
// opt-in path for the agent framework (Phase 5) to use, so an agent's
// DB/API access always goes through this permissioned layer instead of
// touching services or the database directly -- "never let agents have
// unrestricted DB access" from the spec, enforced by construction.
//
// Risk tiers:
//   LOW    -- read-only or fully reversible, no external-facing effect
//             (generating text, creating an internal reminder/notification).
//   MEDIUM -- a real external effect a human should be able to review
//             after the fact (sending a WhatsApp message/email, changing
//             a lead's lifecycle status).
//   HIGH   -- money, legal/compliance documents, or anything hard to
//             undo. invokeTool() below enforces the spec's "HIGH risk
//             requires human approval" rule TODAY, even though the
//             actual human-approval queue (Phase 4) doesn't exist yet:
//             a HIGH-risk tool invoked by a non-manual actor without an
//             explicit context.approved === true is rejected outright.
//             No agent written after this point can bypass that by
//             construction -- there's simply no code path around it.

const { randomUUID } = require('crypto');
const db = require('../db');

const RISK_TIERS = ['LOW', 'MEDIUM', 'HIGH'];
const ACTOR_TYPES = ['manual', 'ai', 'automation', 'system'];

const registry = new Map();

// --- minimal schema validator -------------------------------------------
// No ajv/zod in backend/package.json; every tool input shape registered
// so far is a flat object of primitive/array fields, well within what a
// small hand-rolled checker covers -- consistent with this codebase's
// existing "no new dependency for something this small" pattern (see
// services/webhookSecurity.js, services/leadLifecycle.js).
function validateAgainstSchema(input, schema, path = 'input') {
  const errors = [];
  if (!schema || !schema.type) return errors;

  if (schema.type === 'object') {
    if (typeof input !== 'object' || input === null || Array.isArray(input)) {
      errors.push(`${path} must be an object`);
      return errors;
    }
    for (const key of schema.required || []) {
      if (input[key] === undefined || input[key] === null) errors.push(`${path}.${key} is required`);
    }
    for (const [key, propSchema] of Object.entries(schema.properties || {})) {
      if (input[key] !== undefined && input[key] !== null) {
        errors.push(...validateAgainstSchema(input[key], propSchema, `${path}.${key}`));
      }
    }
    return errors;
  }
  if (schema.type === 'array') {
    if (!Array.isArray(input)) { errors.push(`${path} must be an array`); return errors; }
    if (schema.items) input.forEach((item, i) => errors.push(...validateAgainstSchema(item, schema.items, `${path}[${i}]`)));
    return errors;
  }
  if (schema.type === 'string') {
    if (typeof input !== 'string') errors.push(`${path} must be a string`);
    else if (schema.enum && !schema.enum.includes(input)) errors.push(`${path} must be one of: ${schema.enum.join(', ')}`);
    return errors;
  }
  if (schema.type === 'number') {
    if (typeof input !== 'number' || Number.isNaN(input)) errors.push(`${path} must be a number`);
    return errors;
  }
  if (schema.type === 'boolean') {
    if (typeof input !== 'boolean') errors.push(`${path} must be a boolean`);
    return errors;
  }
  return errors;
}

// --- registration ---------------------------------------------------------

function registerTool({ name, description, riskTier, inputSchema, handler }) {
  if (!name || typeof name !== 'string') throw new Error('registerTool: name is required');
  if (registry.has(name)) throw new Error(`registerTool: a tool named "${name}" is already registered`);
  if (!RISK_TIERS.includes(riskTier)) throw new Error(`registerTool("${name}"): riskTier must be one of ${RISK_TIERS.join(', ')}`);
  if (typeof handler !== 'function') throw new Error(`registerTool("${name}"): handler must be a function`);
  registry.set(name, { name, description: description || '', riskTier, inputSchema: inputSchema || { type: 'object', properties: {} }, handler });
}

function getTool(name) {
  return registry.get(name);
}

function listTools() {
  return [...registry.values()].map(({ name, description, riskTier, inputSchema }) => ({ name, description, riskTier, inputSchema }));
}

// Test-only escape hatch -- lets a fresh test run re-register tools
// without hitting the "already registered" guard above, without giving
// production code any way to silently overwrite a tool.
function _clearRegistryForTests() {
  registry.clear();
}

// --- invocation -------------------------------------------------------------

// context: { tenant_id, actor: { type: 'manual'|'ai'|'automation'|'system', id? }, approved? }
async function invokeTool(name, input, context) {
  const startedAt = Date.now();
  const invocationId = randomUUID();

  const fail = async (errorMessage) => {
    await logInvocation({ id: invocationId, tool: name, context, input, status: 'rejected', errorMessage, durationMs: Date.now() - startedAt });
    throw new Error(errorMessage);
  };

  const tool = registry.get(name);
  if (!tool) return fail(`Unknown tool "${name}". Call listTools() to see what's registered.`);
  if (!context || !context.tenant_id) return fail(`invokeTool("${name}"): context.tenant_id is required`);
  if (!context.actor || !ACTOR_TYPES.includes(context.actor.type)) {
    return fail(`invokeTool("${name}"): context.actor.type must be one of ${ACTOR_TYPES.join(', ')}`);
  }
  if (tool.riskTier === 'HIGH' && context.actor.type !== 'manual' && context.approved !== true) {
    return fail(
      `Tool "${name}" is HIGH risk and was invoked by actor type "${context.actor.type}" without approval. ` +
      `HIGH-risk tools require a human (actor.type === 'manual') or an explicitly approved invocation ` +
      `(context.approved === true) -- there is no autonomous approval queue yet (Phase 4).`
    );
  }

  const schemaErrors = validateAgainstSchema(input, tool.inputSchema);
  if (schemaErrors.length > 0) return fail(`Invalid input for tool "${name}": ${schemaErrors.join('; ')}`);

  try {
    const result = await tool.handler(input, context);
    await logInvocation({ id: invocationId, tool: name, context, input, status: 'succeeded', result, durationMs: Date.now() - startedAt });
    return result;
  } catch (err) {
    await logInvocation({ id: invocationId, tool: name, context, input, status: 'failed', errorMessage: err.message, durationMs: Date.now() - startedAt });
    throw err;
  }
}

// Unconditional audit log -- every invocation is recorded, whether it
// succeeded, failed, or was rejected before the handler even ran, per
// the spec's per-tool audit-logging requirement. A logging failure is
// caught and console.error'd here, never rethrown, so a DB hiccup while
// writing the audit row can't turn an already-successful WhatsApp send
// into a reported failure.
async function logInvocation({ id, tool, context, input, status, result, errorMessage, durationMs }) {
  try {
    await db.prepare(`
      INSERT INTO tool_invocations
        (id, tenant_id, tool_name, actor_type, actor_id, input_json, status, result_summary, error_message, duration_ms)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      id,
      context?.tenant_id || null,
      tool,
      context?.actor?.type || null,
      context?.actor?.id || null,
      JSON.stringify(input ?? null),
      status,
      result !== undefined ? JSON.stringify(result).slice(0, 4000) : null,
      errorMessage || null,
      durationMs,
    );
  } catch (err) {
    console.error(`[toolRegistry] Failed to write audit log for invocation ${id} of "${tool}" (the invocation itself still ${status}):`, err.message);
  }
}

module.exports = {
  registerTool, getTool, listTools, invokeTool,
  RISK_TIERS, ACTOR_TYPES, validateAgainstSchema,
  _clearRegistryForTests,
};
