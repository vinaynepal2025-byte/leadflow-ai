// Unified per-lead activity timeline.
//
// Everything that has ever happened with a lead currently lives in nine
// different tables, each surfaced on its own screen. That's fine for doing
// work, but useless for the question a counsellor actually asks when picking
// up a lead they haven't touched in three weeks: "what's the story here?"
//
// This merges them into one chronological feed. Deliberately assembled in
// application code rather than as a Postgres VIEW: the tables have genuinely
// different shapes and timestamp conventions (some TEXT, some timestamptz),
// several are optional depending on which modules a tenant uses, and a VIEW
// would fail hard the moment one table is missing rather than degrading to
// "that section has no history". Each source is queried in its own try/catch
// so one absent table can never blank the whole timeline.

const express = require('express');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

/// Normalises the mix of timestamp representations to a sortable ISO string.
function normaliseTime(value) {
  if (!value) return null;
  const s = String(value).trim();
  if (!s) return null;

  // 'YYYY-MM-DD HH:MM:SS' — the TEXT convention most tables here use.
  if (/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}/.test(s)) {
    return s.replace(' ', 'T');
  }

  // Anything else (timestamptz from the driver, or a JS Date toString like
  // 'Mon Aug 10 2026 00:18:39 GMT+0545') MUST be coerced. The feed sorts as
  // strings, so a value beginning with a weekday name sorts above every ISO
  // date — silently pinning the OLDEST event to the top of the timeline.
  // Observed live with lead_notes.
  const d = new Date(s);
  if (!Number.isNaN(d.getTime())) {
    return d.toISOString().slice(0, 19);
  }
  return null;
}

async function safeQuery(sql, params) {
  try {
    return await db.prepare(sql).all(...params);
  } catch (err) {
    // A missing or renamed table should cost that one source, not the feed.
    return [];
  }
}

// GET /leads/:id/timeline?limit=100
router.get('/:id/timeline', async (req, res) => {
  const tid = tenantId(req);
  const leadId = req.params.id;
  const limit = Math.min(parseInt(req.query.limit, 10) || 150, 400);

  const lead = await db.prepare('SELECT id, full_name, created_at FROM leads WHERE tenant_id = ? AND id = ?').get(tid, leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const events = [];

  const push = (type, at, title, subtitle, meta) => {
    const t = normaliseTime(at);
    if (!t) return;
    events.push({ type, at: t, title, subtitle: subtitle || null, meta: meta || null });
  };

  // --- Communications (WhatsApp / email / link sends) ---
  for (const r of await safeQuery(
    'SELECT id, channel, direction, body, created_by, created_at FROM communications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC LIMIT 100',
    [tid, leadId],
  )) {
    push('communication', r.created_at,
      `${r.direction === 'inbound' ? 'Received' : 'Sent'} · ${r.channel || 'message'}`,
      r.body ? String(r.body).slice(0, 300) : null,
      { id: r.id, channel: r.channel, direction: r.direction, by: r.created_by });
  }

  // --- Calls ---
  for (const r of await safeQuery(
    'SELECT id, outcome, notes, duration_seconds, called_by, created_at FROM call_logs WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC LIMIT 100',
    [tid, leadId],
  )) {
    push('call', r.created_at,
      `Call · ${String(r.outcome || '').replace(/_/g, ' ')}`,
      r.notes ? String(r.notes).slice(0, 300) : null,
      { id: r.id, outcome: r.outcome, duration_seconds: r.duration_seconds, by: r.called_by });
  }

  // --- Voice notes ---
  for (const r of await safeQuery(
    'SELECT id, transcript, ai_summary, recorded_by, created_at FROM voice_notes WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC LIMIT 50',
    [tid, leadId],
  )) {
    push('voice_note', r.created_at, 'Voice note',
      (r.ai_summary || r.transcript) ? String(r.ai_summary || r.transcript).slice(0, 300) : null,
      { id: r.id, by: r.recorded_by });
  }

  // --- Documents ---
  for (const r of await safeQuery(
    'SELECT id, doc_type, file_name, uploaded_by, created_at FROM documents WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC LIMIT 50',
    [tid, leadId],
  )) {
    push('document', r.created_at, `Document · ${r.doc_type || 'file'}`, r.file_name || null,
      { id: r.id, by: r.uploaded_by });
  }

  // --- Meetings ---
  for (const r of await safeQuery(
    'SELECT id, title, meeting_type, scheduled_at, status, created_at FROM meetings WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC LIMIT 50',
    [tid, leadId],
  )) {
    push('meeting', r.scheduled_at || r.created_at,
      `Meeting · ${r.meeting_type || 'scheduled'}`, r.title || null,
      { id: r.id, status: r.status });
  }

  // --- Lead notes ---
  for (const r of await safeQuery(
    'SELECT id, note_text, author_name, pinned, created_at FROM lead_notes WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC LIMIT 50',
    [tid, leadId],
  )) {
    push('note', r.created_at, r.pinned ? 'Note (pinned)' : 'Note',
      r.note_text ? String(r.note_text).slice(0, 300) : null,
      { id: r.id, by: r.author_name, pinned: r.pinned });
  }

  // --- Fee payments ---
  for (const r of await safeQuery(
    'SELECT id, amount, fee_type, payment_method, status, created_at FROM fee_payments WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC LIMIT 50',
    [tid, leadId],
  )) {
    push('payment', r.created_at,
      `Payment · ${r.amount || ''} ${r.fee_type ? '(' + r.fee_type + ')' : ''}`.trim(),
      r.payment_method || null,
      { id: r.id, status: r.status });
  }

  // --- Offers ---
  for (const r of await safeQuery(
    'SELECT id, offer_text, status, created_at FROM offers WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC LIMIT 50',
    [tid, leadId],
  )) {
    push('offer', r.created_at, `Offer · ${r.status || 'sent'}`,
      r.offer_text ? String(r.offer_text).slice(0, 300) : null,
      { id: r.id, status: r.status });
  }

  // --- Reminders ---
  for (const r of await safeQuery(
    'SELECT id, title, due_at, status, created_at FROM reminders WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC LIMIT 50',
    [tid, leadId],
  )) {
    push('reminder', r.created_at, `Follow-up ${r.status === 'done' ? 'completed' : 'set'}`,
      r.title || null, { id: r.id, due_at: r.due_at, status: r.status });
  }

  // --- The lead itself ---
  push('created', lead.created_at, 'Lead created', lead.full_name || null, { id: lead.id });

  events.sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0));

  res.json({
    lead_id: leadId,
    lead_name: lead.full_name,
    total: events.length,
    events: events.slice(0, limit),
  });
});

module.exports = router;
