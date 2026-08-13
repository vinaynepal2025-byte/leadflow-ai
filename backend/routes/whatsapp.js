const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { sendWhatsAppMessage } = require('../services/whatsapp');
const { createReminder } = require('./reminders');
const { createNotification } = require('./notifications');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// Fills {{lead_name}}, {{institution}}, {{country}} etc. from whatever
// context is available — unresolved placeholders are left as-is rather
// than silently blanked, so a counselor immediately notices if a template
// references data this lead doesn't have.
function fillTemplate(bodyText, context) {
  return bodyText.replace(/\{\{(\w+)\}\}/g, (match, key) => (context[key] !== undefined && context[key] !== null ? context[key] : match));
}

// POST /whatsapp/send  { lead_id, message, created_by }
// Sends via Meta's WhatsApp Cloud API AND logs it in Communication Hub automatically.
router.post('/send', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, message, created_by } = req.body;

  if (!lead_id || !message) {
    return res.status(400).json({ error: 'lead_id and message are required' });
  }

  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });
  if (!lead.phone) return res.status(400).json({ error: 'This lead has no phone number on file' });

  try {
    await sendWhatsAppMessage(lead.phone, message);
  } catch (err) {
    // Still return a clear error to the app — but don't silently fail
    return res.status(502).json({ error: err.message });
  }

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
    VALUES (?, ?, ?, 'whatsapp', 'outbound', ?, ?)
  `).run(id, tid, lead_id, message, created_by || null);

  const logged = await db.prepare('SELECT * FROM communications WHERE id = ?').get(id);
  res.status(201).json({ sent: true, logged });
});


// GET /whatsapp/status — lets the mobile app know whether the paid Meta
// Cloud API path is configured, so it can show/hide the "Send via
// WhatsApp API" option accordingly. Never assume configured — check the
// actual env vars every time (cheap, avoids a stale cached answer if
// Vinay adds credentials while the app is open).
router.get('/status', (req, res) => {
  const configured = Boolean(process.env.WHATSAPP_TOKEN && process.env.WHATSAPP_PHONE_NUMBER_ID);
  res.json({ configured });
});

// ---------- Message templates (tenant-customizable) ----------

router.get('/templates', async (req, res) => {
  const tid = tenantId(req);
  res.json(await db.prepare('SELECT * FROM whatsapp_templates WHERE tenant_id = ? ORDER BY name').all(tid));
});

router.post('/templates', async (req, res) => {
  const tid = tenantId(req);
  const { name, body_text } = req.body;
  if (!name || !body_text) return res.status(400).json({ error: 'name and body_text are required' });
  const id = randomUUID();
  await db.prepare('INSERT INTO whatsapp_templates (id, tenant_id, name, body_text) VALUES (?, ?, ?, ?)')
    .run(id, tid, name, body_text);
  res.status(201).json(await db.prepare('SELECT * FROM whatsapp_templates WHERE id = ?').get(id));
});

router.patch('/templates/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM whatsapp_templates WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Template not found' });
  const { name, body_text } = req.body;
  const updates = [];
  const values = [];
  if (name !== undefined) { updates.push('name = ?'); values.push(name); }
  if (body_text !== undefined) { updates.push('body_text = ?'); values.push(body_text); }
  if (updates.length === 0) return res.status(400).json({ error: 'Nothing to update' });
  values.push(tid, req.params.id);
  await db.prepare(`UPDATE whatsapp_templates SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  res.json(await db.prepare('SELECT * FROM whatsapp_templates WHERE id = ?').get(req.params.id));
});

router.delete('/templates/:id', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare('DELETE FROM whatsapp_templates WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Template not found' });
  res.status(204).send();
});

// GET /whatsapp/templates/:id/preview?lead_id=xxx — resolves {{placeholders}}
// against this specific lead so the counselor sees the actual message
// before sending, not the raw template.
router.get('/templates/:id/preview', async (req, res) => {
  const tid = tenantId(req);
  const template = await db.prepare('SELECT * FROM whatsapp_templates WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!template) return res.status(404).json({ error: 'Template not found' });

  const { lead_id } = req.query;
  let context = {};
  if (lead_id) {
    const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
    if (lead) {
      const app = await db.prepare('SELECT * FROM admission_applications WHERE tenant_id = ? AND lead_id = ? ORDER BY created_at DESC LIMIT 1').get(tid, lead_id);
      context = {
        lead_name: lead.full_name,
        institution: app?.institution_name || '',
        course: app?.course_name || '',
      };
    }
  }
  res.json({ preview: fillTemplate(template.body_text, context) });
});

// ---------- Scheduled sends ----------
//
// Respects the existing safety design: this only sends AUTOMATICALLY
// without a human tap when the paid Meta Cloud API is configured for
// this tenant (the same path POST /send already uses programmatically).
// Without it, "scheduling" a message creates a reminder + notification
// due at send_at instead, with the free wa.me tap-to-send flow — the
// counselor still does the final tap, exactly like every other WhatsApp
// send in this app.

router.post('/schedule', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, body_text, send_at, created_by } = req.body;
  if (!lead_id || !body_text || !send_at) {
    return res.status(400).json({ error: 'lead_id, body_text, and send_at are required' });
  }
  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found for this tenant' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO scheduled_messages (id, tenant_id, lead_id, body_text, send_at, created_by)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, body_text, send_at, created_by || null);

  res.status(201).json(await db.prepare('SELECT * FROM scheduled_messages WHERE id = ?').get(id));
});

router.get('/scheduled', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  const query = lead_id
    ? 'SELECT * FROM scheduled_messages WHERE tenant_id = ? AND lead_id = ? ORDER BY send_at'
    : "SELECT * FROM scheduled_messages WHERE tenant_id = ? AND status = 'pending' ORDER BY send_at";
  const params = lead_id ? [tid, lead_id] : [tid];
  res.json(await db.prepare(query).all(...params));
});

router.delete('/scheduled/:id', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare("DELETE FROM scheduled_messages WHERE tenant_id = ? AND id = ? AND status = 'pending'").run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Scheduled message not found or already sent' });
  res.status(204).send();
});

// POST /whatsapp/process-scheduled — called by an external cron (GitHub
// Actions scheduled workflow, since Render's free tier has no reliable
// background worker). Processes ALL tenants' due messages in one pass;
// no auth beyond what's already in front of the API, intentionally
// simple since it only ever sends what a human already scheduled.
router.post('/process-scheduled', async (req, res) => {
  const due = await db.prepare(
    "SELECT * FROM scheduled_messages WHERE status = 'pending' AND send_at <= datetime('now')"
  ).all();

  const results = [];
  for (const msg of due) {
    const tid = msg.tenant_id;
    const configured = Boolean(process.env.WHATSAPP_TOKEN && process.env.WHATSAPP_PHONE_NUMBER_ID);
    const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, msg.lead_id);

    if (!lead) {
      await db.prepare("UPDATE scheduled_messages SET status = 'failed' WHERE id = ?").run(msg.id);
      results.push({ id: msg.id, status: 'failed', reason: 'lead not found' });
      continue;
    }

    if (configured && lead.phone) {
      try {
        await sendWhatsAppMessage(lead.phone, msg.body_text);
        await db.prepare(`
          INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body)
          VALUES (?, ?, ?, 'whatsapp', 'outbound', ?)
        `).run(randomUUID(), tid, msg.lead_id, msg.body_text);
        await db.prepare("UPDATE scheduled_messages SET status = 'sent', sent_at = datetime('now') WHERE id = ?").run(msg.id);
        results.push({ id: msg.id, status: 'sent' });
      } catch (err) {
        await db.prepare("UPDATE scheduled_messages SET status = 'failed' WHERE id = ?").run(msg.id);
        results.push({ id: msg.id, status: 'failed', reason: err.message });
      }
    } else {
      // No Cloud API — surface it as a reminder + notification so the
      // counselor sends it themselves via the free tap-to-chat flow.
      await createReminder(tid, {
        leadId: msg.lead_id,
        title: `Scheduled WhatsApp ready to send: "${msg.body_text.slice(0, 40)}${msg.body_text.length > 40 ? '...' : ''}"`,
        dueAt: msg.send_at,
      });
      await createNotification(tid, {
        title: `Scheduled message due for ${lead.full_name}`,
        body: msg.body_text,
        linkType: 'lead',
        linkId: msg.lead_id,
      });
      await db.prepare("UPDATE scheduled_messages SET status = 'needs_manual_send', sent_at = datetime('now') WHERE id = ?").run(msg.id);
      results.push({ id: msg.id, status: 'needs_manual_send' });
    }
  }

  res.json({ processed: results.length, results });
});

module.exports = router;
