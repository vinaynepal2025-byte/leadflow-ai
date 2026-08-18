# Future n8n AutomationProvider Contract

**Status: design only. Not wired in.** No code path, environment variable, or
tenant setting anywhere in this repository can select an n8n-backed automation
provider today. `backend/services/automationProvider.js`'s
`getAutomationProvider()` always returns `LocalAutomationEngine`. This document
exists so that if/when a future phase decides to actually integrate n8n, the
contract it must satisfy is already specified and reviewed — not designed under
time pressure at integration time.

This is the last item of the Leads Ecosystem / Agentic AI Runtime redesign
spec's 8-phase plan (Section 37) and directly answers Section 34's
requirement: *"DO NOT TURN LEADFLOW INTO AN n8n WRAPPER... n8n must remain a
future interchangeable automation execution provider... The application must
work fully without n8n today."*

## Why this exists now, unwired

Phases 3-4 of this redesign already built a real, working automation
execution engine (`services/toolRegistry.js` + `services/orchestrator.js`) —
idempotency keys, retry/backoff, dead-letter states, a human-approval queue.
`LocalAutomationEngine` (in `services/automationProvider.js`) is a thin,
same-shape wrapper around that existing engine. The interface below is
written *against* what `LocalAutomationEngine` already does, not against a
hypothetical — every method on it has a real, tested implementation today.

n8n would be a second, swappable implementation of the exact same interface —
useful for a tenant who wants visual workflow editing, or who has existing
n8n workflows they'd rather point at LeadFlow than rebuild as agent code. It
is not, and must never become, the only way LeadFlow's automation works.

## The interface

```js
class AutomationProvider {
  get name();                                            // 'local' | 'n8n' | ...
  async enqueueJob(request: AutomationJobRequest);        // -> job row
  async getJob(tenantId, jobId);                          // -> job row | undefined
  async listJobs(tenantId, filters);                      // -> job row[]
  async approveJob(tenantId, jobId, approvedByUserId);    // -> job row
  async retryJob(tenantId, jobId);                        // -> job row
  async processDueWork(limit);                            // -> { claimed, results }
}
```

`AutomationJobRequest`:

| Field | Type | Notes |
|---|---|---|
| `tenant_id` | string | required |
| `tool_name` | string | required — must be registered in `toolRegistry.js` |
| `tool_input` | object | required |
| `idempotency_key` | string? | durable dedupe, unique per `(tenant_id, idempotency_key)` |
| `initiated_by` | `'manual'\|'ai'\|'automation'\|'system'` | required |
| `initiated_by_id` | string? | e.g. an agent name or user id |
| `max_attempts` | number? | retry ceiling before dead-letter |
| `correlation_id` | string? | ties a chain of related jobs to one logical workflow run (see below) |
| `event` | string? | informational/audit label |

`LocalAutomationEngine` implements every method today by calling straight
into `services/orchestrator.js`'s existing `enqueueJob`/`getJob`(via direct
query)/`approveJob`/`retryDeadLetterJob`/`processDueJobs`. Nothing about
those functions changes — this is an additive interface layered on top, not
a rewrite.

## What a real N8nAutomationEngine would still need to add

The stub in `automationProvider.js` documents the constructor shape
(`webhookBaseUrl`, `signingSecret`, optional `apiKey`) but every method
throws immediately. A real implementation would need:

### 1. Outbound: LeadFlow → n8n

`enqueueJob()` would `POST {webhookBaseUrl}` with the `AutomationJobRequest`
as the body, signed the same way `services/webhookSecurity.js` already
signs/verifies Meta webhooks — `X-Hub-Signature-256`-style HMAC over the raw
body, using `signingSecret`. n8n's own webhook-trigger node would verify it
the same way this codebase already verifies Meta's.

Every outbound request carries:
- `execution_id` — a new UUID minted per attempt, for n8n-side idempotency on their end (distinct from LeadFlow's own `idempotency_key`, which dedupes at *enqueue* time, before n8n is ever called).
- `workflow_id` — which n8n workflow this tool call maps to (a tenant-configurable mapping from `tool_name` → n8n workflow, not yet designed — out of scope for this document).
- `tenant_id` — passed through unchanged, never inferred by n8n.
- `correlation_id` — propagated from the original `AutomationJobRequest` so a human debugging "why did this lead get 4 reminders" can trace every job in one logical run across both systems' logs.

### 2. Inbound: n8n → LeadFlow (the callback)

n8n reports completion via a callback endpoint this repo does not have yet
(e.g. `POST /automation-provider/n8n/callback`), authenticated the same
`X-Hub-Signature-256` way, carrying `execution_id`, `status`
(`succeeded`/`failed`), and a `result` payload. That endpoint would:
1. Verify the signature (reuse `webhookSecurity.js` — it's already generic, not Meta-specific despite living next to the WhatsApp/Lead Ads webhooks).
2. Look up the LeadFlow job by the `execution_id` it minted when calling out.
3. Write the result back through **the exact same
   `runJob()`-shaped success/retry/dead-letter transition**
   `services/orchestrator.js` already implements for locally-executed jobs —
   an n8n-executed job must land in `automation_jobs` looking
   indistinguishable from a local one to everything downstream (the Job
   Queue UI, the Lead Timeline's `AUTOMATION` source tag, audit logging).

### 3. Idempotency across the boundary

LeadFlow's `idempotency_key` (Phase 4) already prevents enqueueing the same
logical job twice. n8n's own workflow *execution* needs its own idempotency
guard too — the `execution_id` above exists so a retried outbound webhook
call (e.g. LeadFlow's own retry/backoff firing before it hears back) doesn't
cause n8n to run the workflow twice. n8n workflows that call back into
LeadFlow tools (e.g. an n8n workflow that itself wants to call
`whatsapp.send_message`) would need to go through the **same Tool Registry**
(`services/toolRegistry.js`) as everything else — never a second, parallel
"n8n has raw API access" path. This is the same "never let agents have
unrestricted DB access" rule from Phase 5, applied to n8n as just another
kind of external actor.

### 4. Tenant isolation

`tenant_id` must never be inferred from the n8n workflow itself — every
inbound callback's `tenant_id` is checked against the job it claims to
complete (`WHERE tenant_id = ? AND id = ?`, same pattern every route in this
codebase already uses), so a misconfigured or malicious n8n instance can't
complete (or forge completion of) another tenant's job.

### 5. What stays LeadFlow's job, never n8n's

Per the spec: risk-tier enforcement (`toolRegistry.js`'s HIGH-risk gate),
tenant isolation, and audit logging (`tool_invocations`) all happen inside
LeadFlow's own Tool Registry — n8n only ever gets to *request* a tool
invocation through `enqueueJob()`/the callback flow above, exactly like every
other `initiated_by` value. It never gets a shortcut around the registry.

## Non-goals (explicitly out of scope until a real integration is greenlit)

- No `tool_name` → n8n `workflow_id` mapping UI/schema.
- No actual HTTP client, retry policy, or timeout handling for calling out to n8n.
- No n8n credential storage (would need the same per-tenant encryption pattern `services/crypto.js` already uses for `tenants.own_brevo_api_key_encrypted`).
- No `POST /automation-provider/n8n/callback` route.
- No environment variables (`N8N_*`) anywhere in `server.js` or `.env` conventions.

Building any of the above is real, separate work for whenever n8n integration
is actually prioritized — this document is the reviewed starting point for
that work, not a promise it's coming next.
