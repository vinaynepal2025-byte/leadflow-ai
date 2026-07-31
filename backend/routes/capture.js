const express = require('express');
const { randomUUID, randomBytes } = require('crypto');
const db = require('../db');
const { createNotification } = require('./notifications');
const { fireEvent } = require('../services/automationEngine');
const { findDuplicates } = require('../services/duplicateDetection');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// ---------- Form management (authenticated side) ----------

router.get('/forms', (req, res) => {
  const tid = tenantId(req);
  res.json(db.prepare('SELECT * FROM capture_forms WHERE tenant_id = ? ORDER BY created_at DESC').all(tid));
});

router.post('/forms', (req, res) => {
  const tid = tenantId(req);
  const { name, channel, assign_to, default_stage, auto_reply_message } = req.body;
  if (!name || !channel) return res.status(400).json({ error: 'name and channel are required' });

  const id = randomUUID();
  // Random, non-sequential key so nobody can enumerate other tenants'
  // forms by guessing — this URL is public by design.
  const publicKey = randomBytes(12).toString('hex');

  db.prepare(`
    INSERT INTO capture_forms (id, tenant_id, public_key, name, channel, assign_to, default_stage, auto_reply_message)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, publicKey, name, channel, assign_to || null, default_stage || 'New', auto_reply_message || null);

  const created = db.prepare('SELECT * FROM capture_forms WHERE id = ?').get(id);
  res.status(201).json({
    ...created,
    submit_url: `/capture/submit/${publicKey}`,
    embed_url: `/capture/form/${publicKey}`,
  });
});

router.patch('/forms/:id', (req, res) => {
  const tid = tenantId(req);
  const existing = db.prepare('SELECT id FROM capture_forms WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Form not found' });

  const allowed = ['name', 'channel', 'assign_to', 'default_stage', 'auto_reply_message', 'active'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) {
      updates.push(`${field} = ?`);
      values.push(field === 'active' ? (req.body[field] ? 1 : 0) : req.body[field]);
    }
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });
  values.push(tid, req.params.id);
  db.prepare(`UPDATE capture_forms SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  res.json(db.prepare('SELECT * FROM capture_forms WHERE id = ?').get(req.params.id));
});

// ---------- Public submission (NO auth — this is the point) ----------

// POST /capture/submit/:publicKey  { full_name, phone, email, message }
// Deliberately minimal and permissive: a public form that rejects real
// enquiries over strict validation loses business. Duplicates are flagged
// on the lead, not rejected, so a parent re-submitting doesn't vanish.
router.post('/submit/:publicKey', (req, res) => {
  const form = db.prepare('SELECT * FROM capture_forms WHERE public_key = ? AND active = 1').get(req.params.publicKey);
  if (!form) return res.status(404).json({ error: 'Form not found or inactive' });

  const { full_name, phone, email, message, course_interest } = req.body;
  if (!full_name || (!phone && !email)) {
    return res.status(400).json({ error: 'Name and at least a phone or email are required' });
  }

  const duplicates = findDuplicates(db, form.tenant_id, { full_name, phone });
  const noteParts = [];
  if (message) noteParts.push(message);
  if (course_interest) noteParts.push(`Interested in: ${course_interest}`);
  if (duplicates.length > 0) {
    noteParts.push(`⚠ Possible duplicate of existing lead "${duplicates[0].full_name}" (${duplicates[0].reasons.join(', ')})`);
  }

  const id = randomUUID();
  db.prepare(`
    INSERT INTO leads (id, tenant_id, full_name, phone, email, source, stage, assigned_to, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, form.tenant_id, full_name, phone || null, email || null,
    `${form.channel}: ${form.name}`, form.default_stage, form.assign_to || null,
    noteParts.join('\n') || null);

  db.prepare('UPDATE capture_forms SET submission_count = submission_count + 1 WHERE id = ?').run(form.id);

  createNotification(form.tenant_id, {
    title: `New enquiry: ${full_name}`,
    body: `Came in via ${form.name}${duplicates.length > 0 ? ' — possible duplicate, check before calling' : ''}`,
    linkType: 'lead',
    linkId: id,
  });

  fireEvent('lead.created', { tenant_id: form.tenant_id, lead_id: id });

  // The submitter gets a plain confirmation — never internal details.
  res.status(201).json({
    success: true,
    message: form.auto_reply_message || 'Thank you! We have received your enquiry and will contact you shortly.',
  });
});

// GET /capture/form/:publicKey — a ready-to-use HTML form.
// Lets a consultancy with no web developer paste one link/iframe on their
// site or behind a QR code and start collecting leads the same day.
router.get('/form/:publicKey', (req, res) => {
  const form = db.prepare('SELECT * FROM capture_forms WHERE public_key = ? AND active = 1').get(req.params.publicKey);
  if (!form) return res.status(404).send('Form not found');

  const tenant = db.prepare('SELECT name, theme_color FROM tenants WHERE id = ?').get(form.tenant_id);
  const color = tenant?.theme_color || '#1B2A4A';
  const orgName = tenant?.name || 'Enquiry Form';

  res.type('html').send(`<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${orgName} — Enquiry</title>
<style>
  body{font-family:system-ui,-apple-system,sans-serif;background:#f7f8fa;margin:0;padding:24px;color:#1a1a1a}
  .card{max-width:420px;margin:0 auto;background:#fff;border-radius:16px;padding:24px;box-shadow:0 2px 16px rgba(0,0,0,.06)}
  h1{font-size:20px;margin:0 0 4px;color:${color}}
  p.sub{color:#666;font-size:13px;margin:0 0 20px}
  label{display:block;font-size:13px;font-weight:600;margin:14px 0 4px}
  input,textarea{width:100%;padding:11px;border:1px solid #ddd;border-radius:10px;font-size:15px;box-sizing:border-box;font-family:inherit}
  button{width:100%;margin-top:20px;padding:14px;background:${color};color:#fff;border:0;border-radius:10px;font-size:15px;font-weight:600;cursor:pointer}
  button:disabled{opacity:.6}
  .msg{margin-top:16px;padding:12px;border-radius:10px;font-size:14px;display:none}
  .ok{background:#e8f5ee;color:#1d6b45}.err{background:#fdeceb;color:#a8342a}
</style></head><body>
<div class="card">
  <h1>${orgName}</h1>
  <p class="sub">Fill this in and our counselor will reach out to you.</p>
  <label>Full Name *</label><input id="n" required>
  <label>Phone</label><input id="p" type="tel" placeholder="With country code">
  <label>Email</label><input id="e" type="email">
  <label>Course of interest</label><input id="c" placeholder="e.g. MBBS in Georgia">
  <label>Message</label><textarea id="m" rows="3"></textarea>
  <button id="b" onclick="send()">Submit Enquiry</button>
  <div id="r" class="msg"></div>
</div>
<script>
async function send(){
  var b=document.getElementById('b'), r=document.getElementById('r');
  var name=document.getElementById('n').value.trim();
  var phone=document.getElementById('p').value.trim();
  var email=document.getElementById('e').value.trim();
  if(!name || (!phone && !email)){
    r.className='msg err'; r.style.display='block';
    r.textContent='Please enter your name and either a phone number or email.'; return;
  }
  b.disabled=true; b.textContent='Sending...';
  try{
    var res=await fetch('/capture/submit/${form.public_key}',{
      method:'POST', headers:{'Content-Type':'application/json'},
      body:JSON.stringify({full_name:name, phone:phone, email:email,
        course_interest:document.getElementById('c').value.trim(),
        message:document.getElementById('m').value.trim()})
    });
    var data=await res.json();
    r.style.display='block';
    if(res.ok){ r.className='msg ok'; r.textContent=data.message;
      ['n','p','e','c','m'].forEach(function(id){document.getElementById(id).value='';});
    } else { r.className='msg err'; r.textContent=data.error||'Something went wrong.'; }
  }catch(err){
    r.style.display='block'; r.className='msg err';
    r.textContent='Could not reach the server. Please try again.';
  }
  b.disabled=false; b.textContent='Submit Enquiry';
}
</script></body></html>`);
});

module.exports = router;
