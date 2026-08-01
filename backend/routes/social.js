const express = require('express');
const { randomUUID, randomBytes } = require('crypto');
const QRCode = require('qrcode');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

const PLATFORMS = ['instagram', 'facebook', 'whatsapp', 'telegram', 'youtube', 'linkedin', 'tiktok', 'offline_qr', 'other'];

/// Share URLs that every major platform exposes publicly. No API keys, no
/// OAuth, no app review — these work today and keep working. Deliberately
/// chosen over the official APIs, which for most of these platforms now
/// require business verification a small consultancy won't get.
function buildShareUrls(link, message) {
  const encodedUrl = encodeURIComponent(link);
  const encodedMsg = encodeURIComponent(message || '');
  const combined = encodeURIComponent(`${message || ''} ${link}`.trim());

  return {
    whatsapp: `https://wa.me/?text=${combined}`,
    telegram: `https://t.me/share/url?url=${encodedUrl}&text=${encodedMsg}`,
    facebook: `https://www.facebook.com/sharer/sharer.php?u=${encodedUrl}`,
    twitter: `https://twitter.com/intent/tweet?url=${encodedUrl}&text=${encodedMsg}`,
    linkedin: `https://www.linkedin.com/sharing/share-offsite/?url=${encodedUrl}`,
    email: `mailto:?subject=${encodedMsg}&body=${combined}`,
    sms: `sms:?body=${combined}`,
    // Instagram and TikTok have no web share endpoint — they only allow
    // link-in-bio or in-app sharing, so we return the raw link to copy
    // rather than pretending a share URL exists.
    instagram_copy: link,
    tiktok_copy: link,
  };
}

// ---------- Tracked link management ----------

router.get('/links', async (req, res) => {
  const tid = tenantId(req);
  const { platform, campaign } = req.query;
  let query = 'SELECT * FROM tracked_links WHERE tenant_id = ?';
  const params = [tid];
  if (platform) {
    query += ' AND platform = ?';
    params.push(platform);
  }
  if (campaign) {
    query += ' AND campaign = ?';
    params.push(campaign);
  }
  query += ' ORDER BY created_at DESC';
  res.json(await db.prepare(query).all(...params));
});

// POST /social/links  { title, platform, capture_form_id? | destination?, campaign?, message? }
router.post('/links', async (req, res) => {
  const tid = tenantId(req);
  const { title, platform, capture_form_id, destination, campaign, message } = req.body;

  if (!title || !platform) return res.status(400).json({ error: 'title and platform are required' });
  if (!PLATFORMS.includes(platform)) {
    return res.status(400).json({ error: `platform must be one of: ${PLATFORMS.join(', ')}` });
  }

  // Most links should point at a capture form — that's what turns a click
  // into a lead. A raw destination is allowed for cases like linking to a
  // brochure or a YouTube campus video.
  let finalDestination = destination;
  if (capture_form_id) {
    const form = await db.prepare('SELECT public_key FROM capture_forms WHERE tenant_id = ? AND id = ?').get(tid, capture_form_id);
    if (!form) return res.status(404).json({ error: 'Capture form not found' });
    finalDestination = `/capture/form/${form.public_key}`;
  }
  if (!finalDestination) {
    return res.status(400).json({ error: 'Either capture_form_id or destination is required' });
  }

  const id = randomUUID();
  const shortCode = randomBytes(4).toString('hex');
  await db.prepare(`
    INSERT INTO tracked_links (id, tenant_id, short_code, title, destination, platform, campaign, capture_form_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, shortCode, title, finalDestination, platform, campaign || null, capture_form_id || null);

  const trackedUrl = `${req.protocol}://${req.get('host')}/s/${shortCode}`;
  res.status(201).json({
    ...await db.prepare('SELECT * FROM tracked_links WHERE id = ?').get(id),
    tracked_url: trackedUrl,
    share_urls: buildShareUrls(trackedUrl, message),
  });
});

// GET /social/links/:id/share?message=... — ready-to-tap share URLs
router.get('/links/:id/share', async (req, res) => {
  const tid = tenantId(req);
  const link = await db.prepare('SELECT * FROM tracked_links WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!link) return res.status(404).json({ error: 'Link not found' });

  const trackedUrl = `${req.protocol}://${req.get('host')}/s/${link.short_code}`;
  res.json({ tracked_url: trackedUrl, share_urls: buildShareUrls(trackedUrl, req.query.message) });
});

// GET /social/links/:id/qr — a real PNG QR code for posters, banners,
// campus notice boards, printed brochures.
router.get('/links/:id/qr', async (req, res) => {
  const tid = tenantId(req);
  const link = await db.prepare('SELECT * FROM tracked_links WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!link) return res.status(404).json({ error: 'Link not found' });

  const trackedUrl = `${req.protocol}://${req.get('host')}/s/${link.short_code}`;
  try {
    const png = await QRCode.toBuffer(trackedUrl, { width: 600, margin: 2, errorCorrectionLevel: 'M' });
    res.type('png').send(png);
  } catch (err) {
    res.status(500).json({ error: `Could not generate QR code: ${err.message}` });
  }
});

router.patch('/links/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM tracked_links WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Link not found' });

  const allowed = ['title', 'campaign', 'active'];
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
  await db.prepare(`UPDATE tracked_links SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  res.json(await db.prepare('SELECT * FROM tracked_links WHERE id = ?').get(req.params.id));
});

// ---------- Attribution analytics ----------

// GET /social/performance — which platform, campaign and individual post
// actually produced leads, not just clicks.
router.get('/performance', async (req, res) => {
  const tid = tenantId(req);

  const byPlatform = await db.prepare(`
    SELECT platform,
           COUNT(*) AS link_count,
           COALESCE(SUM(click_count), 0) AS total_clicks
    FROM tracked_links WHERE tenant_id = ? GROUP BY platform ORDER BY total_clicks DESC
  `).all(tid);

  // Leads carry their source as "channel: form name" from the capture
  // form, so we can join clicks to actual leads per platform.
  const leadsByPlatform = await db.prepare(`
    SELECT SUBSTR(source, 1, INSTR(source, ':') - 1) AS channel,
           COUNT(*) AS leads,
           SUM(CASE WHEN stage = 'Admission' THEN 1 ELSE 0 END) AS admissions
    FROM leads
    WHERE tenant_id = ? AND source LIKE '%:%'
    GROUP BY channel
  `).all(tid);

  const byCampaign = await db.prepare(`
    SELECT COALESCE(campaign, '(no campaign)') AS campaign,
           COUNT(*) AS link_count,
           COALESCE(SUM(click_count), 0) AS total_clicks
    FROM tracked_links WHERE tenant_id = ? GROUP BY campaign ORDER BY total_clicks DESC
  `).all(tid);

  const topLinks = await db.prepare(`
    SELECT id, title, platform, campaign, short_code, click_count
    FROM tracked_links WHERE tenant_id = ? ORDER BY click_count DESC LIMIT 10
  `).all(tid);

  res.json({
    by_platform: byPlatform,
    leads_by_channel: leadsByPlatform,
    by_campaign: byCampaign,
    top_links: topLinks,
  });
});

module.exports = { router, buildShareUrls };
