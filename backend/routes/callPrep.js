// Call preparation — AI talking points for a specific lead.
//
// Mounted separately from calls.js so the call-logging CRUD stays free of
// AI-provider concerns and keeps working normally if the AI provider is
// down or unconfigured.
//
// Design intent: a counselor about to dial has roughly ten seconds to
// remember who this person is. This endpoint answers "what do I say?" using
// only real stored context -- stage, course interest, past call outcomes,
// recent notes -- so the script is grounded in this lead's actual history
// rather than generic sales filler.
//
// The response is strictly validated and clamped before it reaches the
// client, same discipline as the flyer AI-generate endpoint: no raw model
// output is ever trusted or rendered directly.

const express = require('express');
const db = require('../db');
const { generateJson } = require('../services/aiProvider');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

function clampString(v, max) {
  if (typeof v !== 'string') return null;
  const trimmed = v.trim();
  if (!trimmed) return null;
  return trimmed.length > max ? trimmed.slice(0, max) : trimmed;
}

function clampList(v, maxItems, maxLen) {
  if (!Array.isArray(v)) return [];
  return v
    .map((item) => clampString(item, maxLen))
    .filter(Boolean)
    .slice(0, maxItems);
}

// POST /call-prep/:leadId — returns a grounded call script.
router.post('/:leadId', async (req, res) => {
  const tid = tenantId(req);
  const leadId = req.params.leadId;

  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const calls = await db.prepare(
    'SELECT outcome, notes, created_at FROM call_logs WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC LIMIT 5'
  ).all(tid, leadId);

  let notes = [];
  try {
    notes = await db.prepare(
      'SELECT body FROM lead_notes WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC LIMIT 5'
    ).all(tid, leadId);
  } catch (_) {
    // lead_notes is optional context -- a failure here should degrade the
    // script's richness, never block the call prep entirely.
    notes = [];
  }

  const history = calls.length === 0
    ? 'No previous calls logged.'
    : calls
        .map((c) => `- ${c.created_at}: outcome "${c.outcome}"${c.notes ? `, note: ${String(c.notes).slice(0, 200)}` : ''}`)
        .join('\n');

  const noteContext = notes.length === 0
    ? 'No notes recorded.'
    : notes.map((n) => `- ${String(n.body || '').slice(0, 200)}`).join('\n');

  const prompt = `You are coaching an education-admissions counsellor who is about to phone a prospective student or their parent. Prepare them for this specific call.

Lead details:
- Name: ${lead.full_name || 'Unknown'}
- Pipeline stage: ${lead.stage || 'unknown'}
- Course interest: ${lead.course_interest || 'not recorded'}
- City: ${lead.city || 'not recorded'}
- Source: ${lead.source || 'not recorded'}

Recent call history:
${history}

Recent notes:
${noteContext}

Return ONLY a JSON object (no prose, no markdown fences) with exactly these keys:
{
  "opening_line": "<one natural sentence to open the call, under 30 words, referencing something real from the context above>",
  "objective": "<the single most useful outcome for this specific call, under 20 words>",
  "talking_points": ["<3 to 5 short points, each under 20 words, specific to this lead>"],
  "likely_objections": [{"objection": "<what they may say, under 15 words>", "response": "<how to answer honestly, under 30 words>"}],
  "avoid": ["<1 to 3 things not to say or do on this call, each under 15 words>"]
}

Rules: be concrete and grounded in the context provided. Never invent facts about fees, rankings, guarantees, visa outcomes, or admission certainty. If context is thin, say so plainly in the talking points rather than inventing detail. Give at most 3 likely objections.`;

  let raw;
  try {
    // Multi-object array response -- starts at 3000 tokens per the
    // established convention for anything richer than a flat object.
    raw = await generateJson(prompt, { maxTokens: 3000 });
  } catch (err) {
    return res.status(502).json({ error: `Could not prepare call script: ${err.message}` });
  }

  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return res.status(502).json({ error: 'AI returned an unexpected format' });
  }

  const objections = Array.isArray(raw.likely_objections)
    ? raw.likely_objections
        .filter((o) => o && typeof o === 'object')
        .map((o) => ({
          objection: clampString(o.objection, 120),
          response: clampString(o.response, 260),
        }))
        .filter((o) => o.objection && o.response)
        .slice(0, 3)
    : [];

  res.json({
    lead_id: leadId,
    lead_name: lead.full_name || null,
    opening_line: clampString(raw.opening_line, 220) || 'Hello, this is a quick call about your admission enquiry.',
    objective: clampString(raw.objective, 160) || 'Understand where they are in their decision.',
    talking_points: clampList(raw.talking_points, 5, 160),
    likely_objections: objections,
    avoid: clampList(raw.avoid, 3, 120),
    generated_at: new Date().toISOString(),
  });
});

module.exports = router;
