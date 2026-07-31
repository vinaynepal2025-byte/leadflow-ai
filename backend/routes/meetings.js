const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { createNotification } = require('./notifications');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

const MEETING_TYPES = [
  'Counseling', 'Virtual Campus Tour', 'Physical Campus Visit',
  'Parent Meeting', 'Demo Class', 'Other',
];
const STATUSES = ['scheduled', 'completed', 'no-show', 'cancelled', 'rescheduled'];

function parseAttendees(row) {
  if (!row) return row;
  return { ...row, attendees: row.attendees ? JSON.parse(row.attendees) : [] };
}

// GET /meetings?lead_id=xxx&status=scheduled&upcoming=true
router.get('/', (req, res) => {
  const tid = tenantId(req);
  const { lead_id, status, upcoming } = req.query;

  let query = `SELECT m.*, l.full_name AS lead_name, l.phone AS lead_phone
               FROM meetings m JOIN leads l ON l.id = m.lead_id
               WHERE m.tenant_id = ?`;
  const params = [tid];
  if (lead_id) {
    query += ' AND m.lead_id = ?';
    params.push(lead_id);
  }
  if (status) {
    query += ' AND m.status = ?';
    params.push(status);
  }
  if (upcoming === 'true') {
    query += " AND m.scheduled_at >= datetime('now') AND m.status = 'scheduled'";
  }
  query += ' ORDER BY m.scheduled_at ASC';

  res.json(db.prepare(query).all(...params).map(parseAttendees));
});

// POST /meetings — schedule a counseling session, campus tour, etc.
// Also auto-creates a reminder for the counselor so a booked tour can't
// quietly slip past — the single most common way these get missed.
router.post('/', (req, res) => {
  const tid = tenantId(req);
  const {
    lead_id, meeting_type, title, scheduled_at, duration_minutes, mode,
    meeting_link, location, campus_name, host_name, attendees, requested_by,
  } = req.body;

  if (!lead_id || !meeting_type || !title || !scheduled_at) {
    return res.status(400).json({ error: 'lead_id, meeting_type, title, and scheduled_at are required' });
  }
  if (!MEETING_TYPES.includes(meeting_type)) {
    return res.status(400).json({ error: `meeting_type must be one of: ${MEETING_TYPES.join(', ')}` });
  }
  const lead = db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found for this tenant' });

  const id = randomUUID();
  db.prepare(`
    INSERT INTO meetings (id, tenant_id, lead_id, meeting_type, title, scheduled_at, duration_minutes,
                          mode, meeting_link, location, campus_name, host_name, attendees, requested_by)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    id, tid, lead_id, meeting_type, title, scheduled_at, duration_minutes || 30,
    mode || 'online', meeting_link || null, location || null, campus_name || null,
    host_name || null, attendees ? JSON.stringify(attendees) : null, requested_by || null,
  );

  // Reminder 1 hour before, so nobody misses a scheduled tour
  const reminderTime = new Date(new Date(scheduled_at).getTime() - 60 * 60 * 1000).toISOString();
  db.prepare(`
    INSERT INTO reminders (id, tenant_id, lead_id, title, due_at, assigned_to)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(randomUUID(), tid, lead_id, `${meeting_type}: ${title}`, reminderTime, host_name || null);

  // Log it in the communication timeline too, so Audit Center picks it up
  db.prepare(`
    INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
    VALUES (?, ?, ?, 'note', 'outbound', ?, ?)
  `).run(randomUUID(), tid, lead_id, `${meeting_type} scheduled for ${scheduled_at}${campus_name ? ` at ${campus_name}` : ''}`, host_name || null);

  res.status(201).json(parseAttendees(db.prepare('SELECT * FROM meetings WHERE id = ?').get(id)));
});

// PATCH /meetings/:id — reschedule, cancel, or record the outcome
router.patch('/:id', (req, res) => {
  const tid = tenantId(req);
  const existing = db.prepare('SELECT * FROM meetings WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Meeting not found' });

  if (req.body.status && !STATUSES.includes(req.body.status)) {
    return res.status(400).json({ error: `status must be one of: ${STATUSES.join(', ')}` });
  }

  const allowed = [
    'meeting_type', 'title', 'scheduled_at', 'duration_minutes', 'mode', 'meeting_link',
    'location', 'campus_name', 'host_name', 'status', 'outcome_notes', 'interest_level', 'follow_up_required',
  ];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) {
      updates.push(`${field} = ?`);
      values.push(req.body[field]);
    }
  }
  if (req.body.attendees !== undefined) {
    updates.push('attendees = ?');
    values.push(JSON.stringify(req.body.attendees));
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });

  updates.push("updated_at = datetime('now')");
  values.push(tid, req.params.id);
  db.prepare(`UPDATE meetings SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);

  // A no-show is the moment a lead most often goes cold — surface it
  // immediately rather than letting it sit unnoticed in a list.
  if (req.body.status === 'no-show') {
    const lead = db.prepare('SELECT full_name FROM leads WHERE id = ?').get(existing.lead_id);
    createNotification(tid, {
      title: `No-show: ${lead?.full_name || 'lead'}`,
      body: `${existing.meeting_type} — "${existing.title}" was missed. Follow up today.`,
      linkType: 'lead',
      linkId: existing.lead_id,
    });
  }

  // Recording the outcome logs it to the lead's timeline
  if (req.body.outcome_notes) {
    db.prepare(`
      INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
      VALUES (?, ?, ?, 'note', 'outbound', ?, ?)
    `).run(randomUUID(), tid, existing.lead_id,
      `${existing.meeting_type} outcome: ${req.body.outcome_notes}`, existing.host_name || null);
  }

  res.json(parseAttendees(db.prepare('SELECT * FROM meetings WHERE id = ?').get(req.params.id)));
});

// GET /meetings/stats — how campus tours actually convert
router.get('/stats', (req, res) => {
  const tid = tenantId(req);
  const byType = db.prepare(`
    SELECT meeting_type,
           COUNT(*) AS total,
           SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed,
           SUM(CASE WHEN status = 'no-show' THEN 1 ELSE 0 END) AS no_shows
    FROM meetings WHERE tenant_id = ? GROUP BY meeting_type
  `).all(tid);

  // Of the leads who completed a campus tour, how many reached Admission —
  // the number that tells you whether tours are actually worth running.
  const tourConversion = db.prepare(`
    SELECT COUNT(DISTINCT m.lead_id) AS toured,
           COUNT(DISTINCT CASE WHEN l.stage = 'Admission' THEN m.lead_id END) AS converted
    FROM meetings m JOIN leads l ON l.id = m.lead_id
    WHERE m.tenant_id = ? AND m.meeting_type LIKE '%Campus%' AND m.status = 'completed'
  `).get(tid);

  res.json({
    by_type: byType,
    campus_tour_conversion: {
      ...tourConversion,
      rate_percent: tourConversion.toured > 0
        ? Math.round((tourConversion.converted / tourConversion.toured) * 1000) / 10
        : 0,
    },
  });
});

module.exports = router;
