const { randomUUID } = require('crypto');
const db = require('../db');
const { createNotification } = require('../routes/notifications');

/// Called from other route files when something notable happens.
/// event: 'lead.created' | 'lead.stage_changed' | 'document.rejected'
/// context: { tenant_id, lead_id, ...event-specific fields }
///
/// v1 supports two action types (create_reminder, create_notification) —
/// deliberately small and real rather than a large unimplemented list.
/// The trigger/condition/action shape is designed so more of each can be
/// added later without changing this function's structure.
function fireEvent(event, context) {
  const rules = db.prepare(
    'SELECT * FROM automation_rules WHERE tenant_id = ? AND trigger_event = ? AND enabled = 1'
  ).all(context.tenant_id, event);

  for (const rule of rules) {
    if (rule.condition_field && rule.condition_value) {
      if (context[rule.condition_field] !== rule.condition_value) continue; // condition didn't match
    }

    let config;
    try {
      config = JSON.parse(rule.action_config);
    } catch {
      continue; // malformed rule config — skip rather than crash the triggering request
    }

    if (rule.action_type === 'create_reminder' && context.lead_id) {
      const dueAt = new Date(Date.now() + (config.offset_days || 1) * 86400000).toISOString();
      db.prepare(`
        INSERT INTO reminders (id, tenant_id, lead_id, title, due_at, assigned_to)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(randomUUID(), context.tenant_id, context.lead_id, config.title || 'Follow up', dueAt, config.assigned_to || null);
    }

    if (rule.action_type === 'create_notification') {
      createNotification(context.tenant_id, {
        title: config.title || 'Automation triggered',
        body: config.body || null,
        linkType: 'lead',
        linkId: context.lead_id || null,
      });
    }
  }
}

module.exports = { fireEvent };
