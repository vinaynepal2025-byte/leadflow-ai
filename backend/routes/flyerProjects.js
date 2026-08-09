const express = require('express');
const multer = require('multer');
const { randomUUID } = require('crypto');
const db = require('../db');
const { uploadFile, getSignedUrl } = require('../services/supabaseStorage');
const { generateJson } = require('../services/aiProvider');

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

async function attachUrls(row) {
  if (!row) return row;
  const out = { ...row };
  if (row.background_image_path) {
    try { out.background_image_url = await getSignedUrl(row.background_image_path, 3600); }
    catch (_) { out.background_image_url = null; }
  }
  if (row.rendered_image_path) {
    try { out.rendered_image_url = await getSignedUrl(row.rendered_image_path, 3600); }
    catch (_) { out.rendered_image_url = null; }
  }
  return out;
}

// GET /flyer-projects?lead_id=xxx
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id } = req.query;
  const rows = lead_id
    ? await db.prepare('SELECT * FROM flyer_projects WHERE tenant_id = ? AND lead_id = ? ORDER BY updated_at DESC').all(tid, lead_id)
    : await db.prepare('SELECT * FROM flyer_projects WHERE tenant_id = ? ORDER BY updated_at DESC LIMIT 50').all(tid);
  res.json(await Promise.all(rows.map(attachUrls)));
});

// GET /flyer-projects/:id
router.get('/:id', async (req, res) => {
  const tid = tenantId(req);
  const row = await db.prepare('SELECT * FROM flyer_projects WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!row) return res.status(404).json({ error: 'Flyer project not found' });
  res.json(await attachUrls(row));
});

// POST /flyer-projects — create a new project (blank canvas or pre-filled
// from a starter-template's element array, passed in as canvas_json).
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { title, lead_id, canvas_width, canvas_height, canvas_json, background_color, created_by } = req.body;

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO flyer_projects (id, tenant_id, lead_id, title, canvas_width, canvas_height, canvas_json, background_color, created_by)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    id, tid, lead_id || null, title || 'Untitled Flyer',
    canvas_width || 1080, canvas_height || 1350,
    JSON.stringify(canvas_json || []), background_color || '#FFFFFF', created_by || null,
  );

  res.status(201).json(await attachUrls(await db.prepare('SELECT * FROM flyer_projects WHERE id = ?').get(id)));
});

// PATCH /flyer-projects/:id — autosave: title, canvas_json (full element
// array replace — the client owns the whole canvas state and pushes it
// wholesale on every edit-session save, simpler and safer than diffing
// individual elements server-side), background_color.
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM flyer_projects WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Flyer project not found' });

  const allowed = ['title', 'background_color', 'canvas_width', 'canvas_height'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) { updates.push(field + ' = ?'); values.push(req.body[field]); }
  }
  if (req.body.canvas_json !== undefined) {
    updates.push('canvas_json = ?');
    values.push(JSON.stringify(req.body.canvas_json));
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });

  updates.push('updated_at = now()');
  values.push(tid, req.params.id);
  await db.prepare('UPDATE flyer_projects SET ' + updates.join(', ') + ' WHERE tenant_id = ? AND id = ?').run(...values);

  res.json(await attachUrls(await db.prepare('SELECT * FROM flyer_projects WHERE id = ?').get(req.params.id)));
});

// POST /flyer-projects/:id/background  (multipart: file=<image>)
// Uploads a background image (photo behind the design elements).
router.post('/:id/background', upload.single('file'), async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM flyer_projects WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Flyer project not found' });
  if (!req.file) return res.status(400).json({ error: 'file is required' });

  const storagePath = `flyer-backgrounds/${tid}/${req.params.id}-${randomUUID()}-${req.file.originalname}`;
  try {
    await uploadFile(req.file.buffer, storagePath, req.file.mimetype);
  } catch (err) {
    return res.status(502).json({ error: `Upload failed: ${err.message}` });
  }

  await db.prepare("UPDATE flyer_projects SET background_image_path = ?, updated_at = now() WHERE tenant_id = ? AND id = ?")
    .run(storagePath, tid, req.params.id);

  res.json(await attachUrls(await db.prepare('SELECT * FROM flyer_projects WHERE id = ?').get(req.params.id)));
});

// POST /flyer-projects/:id/element-image  (multipart: file=<image>)
// Uploads an image meant to be placed as a moveable canvas element (a
// photo, an icon, a graphic — separate from the background and from the
// tenant's saved logos). Returns just the signed URL; the client is
// responsible for adding an element to canvas_json referencing it via a
// subsequent PATCH.
router.post('/:id/element-image', upload.single('file'), async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM flyer_projects WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Flyer project not found' });
  if (!req.file) return res.status(400).json({ error: 'file is required' });

  const storagePath = `flyer-elements/${tid}/${req.params.id}-${randomUUID()}-${req.file.originalname}`;
  try {
    await uploadFile(req.file.buffer, storagePath, req.file.mimetype);
  } catch (err) {
    return res.status(502).json({ error: `Upload failed: ${err.message}` });
  }

  const imageUrl = await getSignedUrl(storagePath, 3600);
  res.status(201).json({ storage_path: storagePath, image_url: imageUrl });
});

// POST /flyer-projects/:id/render  (multipart: file=<final PNG>)
// The client renders the finished canvas locally (RepaintBoundary ->
// toImage -> PNG bytes) and uploads the result here. No server-side
// rendering engine is involved at all for the new canvas flow -- this
// sidesteps the sharp/libvips native-binary fragility entirely and means
// the final image always matches exactly what the counselor saw on
// screen, pixel for pixel.
router.post('/:id/render', upload.single('file'), async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM flyer_projects WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Flyer project not found' });
  if (!req.file) return res.status(400).json({ error: 'file is required' });

  const storagePath = `flyer-renders/${tid}/${req.params.id}-${Date.now()}.png`;
  try {
    await uploadFile(req.file.buffer, storagePath, 'image/png');
  } catch (err) {
    return res.status(502).json({ error: `Upload failed: ${err.message}` });
  }

  await db.prepare("UPDATE flyer_projects SET rendered_image_path = ?, updated_at = now() WHERE tenant_id = ? AND id = ?")
    .run(storagePath, tid, req.params.id);

  res.json(await attachUrls(await db.prepare('SELECT * FROM flyer_projects WHERE id = ?').get(req.params.id)));
});

// POST /flyer-projects/:id/ai-generate
// Prompt -> AI-proposed canvas layout. Does NOT auto-save -- the client
// previews the result and only persists it via the existing PATCH once
// the counselor confirms (see routes/flyerProjects.js PATCH /:id and the
// Flutter FlyerStudioScreen._generateWithAI flow). Every field is
// validated/clamped before it ever reaches a client render -- the AI's
// raw output is never trusted directly, same philosophy as
// routes/ai.js's theme generator.
router.post('/:id/ai-generate', async (req, res) => {
  const tid = tenantId(req);
  const project = await db.prepare('SELECT * FROM flyer_projects WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!project) return res.status(404).json({ error: 'Flyer project not found' });

  const { prompt } = req.body;
  if (!prompt || typeof prompt !== 'string' || !prompt.trim()) {
    return res.status(400).json({ error: 'prompt is required' });
  }

  const canvasW = project.canvas_width || 1080;
  const canvasH = project.canvas_height || 1350;
  const KNOWN_FONTS = ['SpaceGrotesk','Inter','PlayfairDisplay','Lato','Poppins','Roboto','Montserrat','OpenSans'];

  const aiPrompt = `You are a graphic designer for an education-admissions consultancy. Design a promotional flyer layout as a JSON array of elements for a canvas that is ${canvasW}x${canvasH} pixels.

Brief: "${prompt.trim()}"

Return ONLY a JSON array (no prose, no markdown fences). Each element must be one of:
- Text element: {"type":"text","x":<number>,"y":<number>,"width":<number>,"height":<number>,"text":"<short punchy copy>","fontSize":<8-120>,"fontFamily":"<one of ${KNOWN_FONTS.join(', ')}>","color":"<#RRGGBB hex>","fontWeight":"normal"|"bold","textAlign":"left"|"center"|"right"}
- Image placeholder: {"type":"image","x":<number>,"y":<number>,"width":<number>,"height":<number>,"url":""}

Rules: 4-8 elements total. All x/y/width/height must fit within the ${canvasW}x${canvasH} canvas (x>=0, y>=0, x+width<=${canvasW}, y+height<=${canvasH}). Include a headline, supporting text, and at least one image placeholder for a photo/logo spot. Use a color palette that fits the brief's tone. Never include rotation.`;

  let rawElements;
  try {
    rawElements = await generateJson(aiPrompt, { maxTokens: 3500 });
  } catch (err) {
    return res.status(502).json({ error: `AI generation failed: ${err.message}` });
  }
  if (!Array.isArray(rawElements)) {
    return res.status(502).json({ error: 'AI returned an unexpected format' });
  }

  const hexRe = /^#[0-9A-Fa-f]{6}$/;
  const clampNum = (v, lo, hi, fallback) => {
    const n = Number(v);
    if (!Number.isFinite(n)) return fallback;
    return Math.min(hi, Math.max(lo, n));
  };

  const validated = rawElements
    .filter((el) => el && (el.type === 'text' || el.type === 'image'))
    .slice(0, 12)
    .map((el, i) => {
      const width = clampNum(el.width, 20, canvasW, 200);
      const height = clampNum(el.height, 20, canvasH, 80);
      const x = clampNum(el.x, 0, Math.max(0, canvasW - width), 0);
      const y = clampNum(el.y, 0, Math.max(0, canvasH - height), 0);
      const base = {
        id: `ai-${Date.now()}-${i}`,
        type: el.type,
        x, y, width, height,
        rotation: 0,
        zIndex: i,
      };
      if (el.type === 'text') {
        return {
          ...base,
          text: typeof el.text === 'string' ? el.text.slice(0, 200) : 'Text',
          fontSize: clampNum(el.fontSize, 8, 120, 24),
          fontFamily: KNOWN_FONTS.includes(el.fontFamily) ? el.fontFamily : 'Roboto',
          color: hexRe.test(el.color) ? el.color : '#000000',
          fontWeight: el.fontWeight === 'bold' ? 'bold' : 'normal',
          textAlign: ['left', 'center', 'right'].includes(el.textAlign) ? el.textAlign : 'left',
        };
      }
      return { ...base, url: '', fit: 'cover' };
    });

  if (validated.length === 0) {
    return res.status(502).json({ error: 'AI returned no usable elements' });
  }

  res.json({ canvas_json: validated });
});

// DELETE /flyer-projects/:id
router.delete('/:id', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare('DELETE FROM flyer_projects WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Flyer project not found' });
  res.status(200).json({ deleted: true });
});

module.exports = router;
