// Calls module.
//
// The `call_logs` table already carried duration_seconds, direction,
// phone_used, follow_up_at and channel long before anything read them --
// the previous version of this file only exposed GET / and POST /, so most
// of the schema was dead weight. This rewrite uses all of it and adds the
// three things that make call logging actually worth a counselor's time:
//
// 1. Outcome-driven follow-ups: choosing "No answer" or "Call back later"
//    creates a real reminder row, so a missed call can't silently fall out
//    of the pipeline. The reminder id is stored back on the call, so
//    editing a call updates its reminder instead of creating a second one.
// 2. Stats per lead: attempts, connect rate, average talk time, last
//    outcome -- the numbers that tell a counselor whether to keep dialling
//    or switch to WhatsApp.
// 3. Best time to call: derived from when this lead's calls actually
//    connected, falling back to tenant-wide data while a lead has too
//    little history to say anything honest.
//
// Timestamps in this database are TEXT in 'YYYY-MM-DD HH24:MI:SS' form
// (a long-standing convention here), so time-of-day analysis parses with
// substring/to_timestamp rather than native date functions.

const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// Outcomes that mean a human actually spoke to a human. Used for connect
// rate and for best-time-to-call, so both stay meaningful if new outcome
// values get added later.
const CONNECTED_OUTCOMES = ['connected', 'interested', 'not_interested', 'callback_requested'];

// Outcomes that should automatically schedule a follow-up, and how far out.
const AUTO_FOLLOWUP_HOURS = {
  no_answer: 4,
  busy: 2,
  switched_off: 24,
  callback_requested: 24,
};

function nowText() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

function textTimestamp(date) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

// GET /calls?lead_id=xxx  — call history, newest first.
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  const rows = lead_id
    ? await db.prepare('SELECT * FROM call_logs WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC').all(tid, lead_id)
    : await db.prepare('SELECT * FROM call_logs WHERE tenant_id = ? ORDER BY created_at DESC LIMIT 100').all(tid);
  res.json(rows);
});

// GET /calls/stats?lead_id=xxx — the numbers a counselor actually acts on.
router.get('/stats', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  if (!lead_id) return res.status(400).json({ error: 'lead_id is required' });

  const rows = await db.prepare(
    'SELECT outcome, duration_seconds, created_at FROM call_logs WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC'
  ).all(tid, lead_id);

  const total = rows.length;
  const connected = rows.filter((r) => CONNECTED_OUTCOMES.includes(r.outcome)).length;
  const talkSeconds = rows.reduce((sum, r) => sum + (Number(r.duration_seconds) || 0), 0);
  const connectedWithDuration = rows.filter(
    (r) => CONNECTED_OUTCOMES.includes(r.outcome) && Number(r.duration_seconds) > 0
  );

  res.json({
    total_attempts: total,
    connected_count: connected,
    connect_rate: total === 0 ? null : Math.round((connected / total) * 100),
    total_talk_seconds: talkSeconds,
    avg_talk_seconds: connectedWithDuration.length === 0
      ? null
      : Math.round(
          connectedWithDuration.reduce((s, r) => s + Number(r.duration_seconds), 0) /
            connectedWithDuration.length
        ),
    last_outcome: total === 0 ? null : rows[0].outcome,
    last_called_at: total === 0 ? null : rows[0].created_at,
  });
});

// GET /calls/best-time?lead_id=xxx
// Which hour-of-day this lead has actually answered in. Falls back to
// tenant-wide history when the lead has too few connected calls to say
// anything honest -- a single answered call is not a pattern, and
// pretending otherwise would send counselors chasing noise.
router.get('/best-time', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;

  const placeholders = CONNECTED_OUTCOMES.map(() => '?').join(',');

  let scope = 'lead';
  let rows = [];
  if (lead_id) {
    rows = await db.prepare(
      `SELECT created_at FROM call_logs
       WHERE tenant_id = ? AND lead_id = ? AND outcome IN (${placeholders})`
    ).all(tid, lead_id, ...CONNECTED_OUTCOMES);
  }

  const MIN_SAMPLE = 3;
  if (rows.length < MIN_SAMPLE) {
    scope = 'tenant';
    rows = await db.prepare(
      `SELECT created_at FROM call_logs
       WHERE tenant_id = ? AND outcome IN (${placeholders})`
    ).all(tid, ...CONNECTED_OUTCOMES);
  }

  if (rows.length < MIN_SAMPLE) {
    return res.json({
      scope: 'none',
      sample_size: rows.length,
      best_hour: null,
      message: 'Not enough connected calls yet to suggest a best time.',
    });
  }

  // created_at is 'YYYY-MM-DD HH:MM:SS' text, so the hour is chars 12-13.
  const buckets = {};
  for (const r of rows) {
    const hour = parseInt(String(r.created_at).substring(11, 13), 10);
    if (Number.isNaN(hour)) continue;
    buckets[hour] = (buckets[hour] || 0) + 1;
  }

  const ranked = Object.entries(buckets)
    .map(([hour, count]) => ({ hour: Number(hour), count }))
    .sort((a, b) => b.count - a.count);

  if (ranked.length === 0) {
    return res.json({ scope: 'none', sample_size: 0, best_hour: null });
  }

  const fmt = (h) => {
    const suffix = h < 12 ? 'AM' : 'PM';
    const display = h % 12 === 0 ? 12 : h % 12;
    return `${display} ${suffix}`;
  };

  res.json({
    scope,
    sample_size: rows.length,
    best_hour: ranked[0].hour,
    best_hour_label: `${fmt(ranked[0].hour)} – ${fmt((ranked[0].hour + 1) % 24)}`,
    top_hours: ranked.slice(0, 3).map((r) => ({
      hour: r.hour,
      label: `${fmt(r.hour)} – ${fmt((r.hour + 1) % 24)}`,
      connected_count: r.count,
    })),
    message: scope === 'tenant'
      ? 'Based on all your connected calls (this lead has too little history yet).'
      : 'Based on when this lead has actually answered.',
  });
});

// POST /calls — log a call.
// Creates a follow-up reminder automatically for outcomes that imply one,
// unless the caller passes an explicit follow_up_at (or explicitly opts out
// with auto_follow_up: false).
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const {
    lead_id,
    outcome,
    notes,
    called_by,
    duration_seconds,
    direction,
    phone_used,
    channel,
    follow_up_at,
    auto_follow_up,
    sentiment,
  } = req.body;

  if (!lead_id || !outcome) {
    return res.status(400).json({ error: 'lead_id and outcome are required' });
  }

  // Older builds of the mobile app wrote hyphenated outcomes ('no-answer'),
  // while the follow-up rules below key off underscores. Normalising on
  // write means a stale client can't silently lose its follow-up reminders,
  // and stats/best-time don't split one outcome across two spellings.
  const normalisedOutcome = String(outcome).trim().toLowerCase().replace(/-/g, '_');

  const lead = await db.prepare('SELECT id, full_name FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  // Work out the follow-up time: explicit value wins, otherwise derive one
  // from the outcome, otherwise none.
  let followUp = follow_up_at || null;
  if (!followUp && auto_follow_up !== false && AUTO_FOLLOWUP_HOURS[normalisedOutcome]) {
    const d = new Date();
    d.setHours(d.getHours() + AUTO_FOLLOWUP_HOURS[normalisedOutcome]);
    followUp = textTimestamp(d);
  }

  let reminderId = null;
  if (followUp) {
    reminderId = randomUUID();
    const label = {
      no_answer: 'Retry call (no answer)',
      busy: 'Retry call (line was busy)',
      switched_off: 'Retry call (phone was off)',
      callback_requested: 'Callback requested',
    }[normalisedOutcome] || 'Follow-up call';
    await db.prepare(
      'INSERT INTO reminders (id, tenant_id, lead_id, title, due_at, assigned_to, status) VALUES (?, ?, ?, ?, ?, ?, ?)'
    ).run(reminderId, tid, lead_id, `${label} — ${lead.full_name}`, followUp, called_by || null, 'pending');
  }

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO call_logs
      (id, tenant_id, lead_id, duration_seconds, outcome, notes, called_by,
       created_at, direction, phone_used, follow_up_at, channel, reminder_id, sentiment)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    id, tid, lead_id,
    Number.isFinite(Number(duration_seconds)) ? Number(duration_seconds) : null,
    normalisedOutcome, notes || null, called_by || null,
    nowText(),
    direction || 'outbound', phone_used || null, followUp, channel || 'phone',
    reminderId, sentiment || null,
  );

  const created = await db.prepare('SELECT * FROM call_logs WHERE id = ?').get(id);
  res.status(201).json(created);
});

// PATCH /calls/:id — fix a mis-logged call. Previously impossible: an
// accidental wrong outcome was permanent, which quietly poisons connect-rate
// and best-time data forever.
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT * FROM call_logs WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Call log not found' });

  const allowed = ['outcome', 'notes', 'duration_seconds', 'direction', 'phone_used', 'channel', 'follow_up_at', 'sentiment'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) {
      updates.push(field + ' = ?');
      values.push(req.body[field]);
    }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });

  values.push(tid, req.params.id);
  await db.prepare('UPDATE call_logs SET ' + updates.join(', ') + ' WHERE tenant_id = ? AND id = ?').run(...values);

  // Keep the linked reminder in step with an edited follow-up time rather
  // than leaving a stale reminder pointing at the old slot.
  if (req.body.follow_up_at !== undefined && existing.reminder_id) {
    if (req.body.follow_up_at) {
      await db.prepare('UPDATE reminders SET due_at = ? WHERE tenant_id = ? AND id = ?')
        .run(req.body.follow_up_at, tid, existing.reminder_id);
    } else {
      await db.prepare('UPDATE reminders SET status = ? WHERE tenant_id = ? AND id = ?')
        .run('cancelled', tid, existing.reminder_id);
    }
  }

  res.json(await db.prepare('SELECT * FROM call_logs WHERE id = ?').get(req.params.id));
});

// DELETE /calls/:id — remove a call log and cancel any reminder it created.
router.delete('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT * FROM call_logs WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Call log not found' });

  if (existing.reminder_id) {
    await db.prepare('UPDATE reminders SET status = ? WHERE tenant_id = ? AND id = ?')
      .run('cancelled', tid, existing.reminder_id);
  }
  await db.prepare('DELETE FROM call_logs WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  res.json({ deleted: true });
});

module.exports = router;
