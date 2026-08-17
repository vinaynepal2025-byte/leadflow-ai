const express = require('express');
const multer = require('multer');
const { randomUUID } = require('crypto');
const QRCode = require('qrcode');
const db = require('../db');
const { uploadFile, getSignedUrl } = require('../services/supabaseStorage');
const { generateJson } = require('../services/aiProvider');
const { buildWhatsAppLink } = require('../services/phone');

const HEX_COLOR_RE = /^#[0-9a-fA-F]{6}$/;

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

// sharp is loaded lazily -- same deliberate safety choice as
// routes/tenantLogos.js: if sharp fails to load, only export conversion
// fails, the rest of this route file (including autosave, the whole
// editor) keeps working.
let sharpModule = null;
let sharpLoadError = null;
function getSharp() {
  if (sharpModule) return sharpModule;
  if (sharpLoadError) throw sharpLoadError;
  try {
    sharpModule = require('sharp');
    return sharpModule;
  } catch (err) {
    sharpLoadError = err;
    throw err;
  }
}

// Wraps a PNG buffer in a minimal single-image ICO container (the
// Vista+ format, where an ICO entry can hold raw PNG bytes directly --
// every modern browser/OS accepts this for a favicon). sharp has no ICO
// encoder, and pulling in a new dependency for ~20 lines of binary
// header-writing didn't clear the Dependency Policy bar (master spec
// §36) -- this is a real, spec-correct ICO file, not a renamed PNG.
function pngToIco(pngBuffer, size) {
  const iconDir = Buffer.alloc(6);
  iconDir.writeUInt16LE(0, 0); // reserved
  iconDir.writeUInt16LE(1, 2); // type: icon
  iconDir.writeUInt16LE(1, 4); // image count

  const entry = Buffer.alloc(16);
  const dim = size >= 256 ? 0 : size; // 0 means "256" in ICO's 1-byte field
  entry.writeUInt8(dim, 0); // width
  entry.writeUInt8(dim, 1); // height
  entry.writeUInt8(0, 2); // color count (0 = not palette-based)
  entry.writeUInt8(0, 3); // reserved
  entry.writeUInt16LE(1, 4); // color planes
  entry.writeUInt16LE(32, 6); // bits per pixel
  entry.writeUInt32LE(pngBuffer.length, 8); // size of image data
  entry.writeUInt32LE(6 + 16, 12); // offset of image data from file start

  return Buffer.concat([iconDir, entry, pngBuffer]);
}

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

// POST /flyer-projects/:id/duplicate — copies title/canvas/elements/
// background into a brand-new project (its own id, its own autosave
// history from here on). Does not carry over rendered_image_path -- a
// duplicate is a fresh editing session, not a copy of a specific past
// export, and the two should never appear to share one exported image.
router.post('/:id/duplicate', async (req, res) => {
  const tid = tenantId(req);
  const source = await db.prepare('SELECT * FROM flyer_projects WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!source) return res.status(404).json({ error: 'Flyer project not found' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO flyer_projects (id, tenant_id, lead_id, title, canvas_width, canvas_height, canvas_json, background_color, background_image_path, ai_generated, created_by)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    id, tid, source.lead_id, `Copy of ${source.title || 'Untitled'}`,
    source.canvas_width, source.canvas_height, JSON.stringify(source.canvas_json),
    source.background_color, source.background_image_path, source.ai_generated, source.created_by,
  );

  res.status(201).json(await attachUrls(await db.prepare('SELECT * FROM flyer_projects WHERE id = ?').get(id)));
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

// POST /flyer-projects/:id/qrcode  { data, fg?, bg? }
// A QR code as a real, scannable, resizable canvas element (Canva-parity
// Phase G) -- generated server-side with the `qrcode` package (already a
// backend dependency, used for tracked-link QR codes in routes/social.js),
// uploaded to storage, and returned the same shape as element-image above
// so the client adds it to canvas_json exactly like any other image
// element. Re-called whenever the user edits the encoded text/colours to
// regenerate the PNG in place.
router.post('/:id/qrcode', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT id FROM flyer_projects WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Flyer project not found' });

  const data = (req.body.data || '').toString().trim();
  if (!data) return res.status(400).json({ error: 'data is required' });
  if (data.length > 2000) return res.status(400).json({ error: 'data is too long for a scannable QR code' });

  const fg = HEX_COLOR_RE.test(req.body.fg) ? req.body.fg : '#000000';
  const bg = HEX_COLOR_RE.test(req.body.bg) ? req.body.bg : '#FFFFFF';

  let png;
  try {
    png = await QRCode.toBuffer(data, {
      width: 600,
      margin: 2,
      errorCorrectionLevel: 'M',
      color: { dark: fg, light: bg },
    });
  } catch (err) {
    return res.status(400).json({ error: `Could not generate QR code: ${err.message}` });
  }

  const storagePath = `flyer-elements/${tid}/${req.params.id}-qr-${randomUUID()}.png`;
  try {
    await uploadFile(png, storagePath, 'image/png');
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

// POST /flyer-projects/:id/export  (multipart: file=<PNG>, format=png|jpg|webp|favicon, width?, height?)
// Takes the client's captured canvas PNG and returns a genuinely
// converted file -- real format conversion via sharp, never the same
// bytes relabeled with a different extension. Also archives the result
// to the tenant's Asset Library as a best-effort background step (never
// blocks the response the counsellor is waiting on to actually share
// the file), same "sharing is the actual intent" philosophy as /render.
router.post('/:id/export', upload.single('file'), async (req, res) => {
  const tid = tenantId(req);
  const project = await db.prepare('SELECT id FROM flyer_projects WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!project) return res.status(404).json({ error: 'Flyer project not found' });
  if (!req.file) return res.status(400).json({ error: 'file is required' });

  const format = (req.body.format || 'png').toLowerCase();
  if (!['png', 'jpg', 'webp', 'favicon'].includes(format)) {
    return res.status(400).json({ error: 'format must be one of: png, jpg, webp, favicon' });
  }
  const width = req.body.width ? parseInt(req.body.width, 10) : null;
  const height = req.body.height ? parseInt(req.body.height, 10) : null;

  let sharpFn;
  try {
    sharpFn = getSharp();
  } catch (err) {
    return res.status(502).json({ error: 'Image engine unavailable' });
  }

  let outBuffer, ext, mime;
  try {
    if (format === 'favicon') {
      const size = width || 32;
      const pngBuf = await sharpFn(req.file.buffer)
        .resize(size, size, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
        .png()
        .toBuffer();
      outBuffer = pngToIco(pngBuf, size);
      ext = 'ico';
      mime = 'image/x-icon';
    } else {
      let pipeline = sharpFn(req.file.buffer);
      if (width && height) {
        pipeline = pipeline.resize(width, height, {
          fit: 'contain',
          background: { r: 0, g: 0, b: 0, alpha: 0 },
        });
      }
      if (format === 'jpg') {
        outBuffer = await pipeline.flatten({ background: '#FFFFFF' }).jpeg({ quality: 92 }).toBuffer();
        ext = 'jpg';
        mime = 'image/jpeg';
      } else if (format === 'webp') {
        outBuffer = await pipeline.webp({ quality: 92 }).toBuffer();
        ext = 'webp';
        mime = 'image/webp';
      } else {
        outBuffer = await pipeline.png().toBuffer();
        ext = 'png';
        mime = 'image/png';
      }
    }
  } catch (err) {
    return res.status(502).json({ error: `Export conversion failed: ${err.message}` });
  }

  // Fire-and-forget archive to the Asset Library.
  (async () => {
    try {
      const storagePath = `flyer-exports/${tid}/${req.params.id}-${Date.now()}.${ext}`;
      await uploadFile(outBuffer, storagePath, mime);
      await db.prepare(`
        INSERT INTO tenant_assets (id, tenant_id, kind, label, storage_path)
        VALUES (?, ?, 'export', ?, ?)
      `).run(randomUUID(), tid, req.body.label || null, storagePath);
    } catch (_) {
      // Silent -- this is a backup path, not the request's actual purpose.
    }
  })();

  res.set('Content-Type', mime);
  res.set('Content-Disposition', `attachment; filename="export.${ext}"`);
  res.status(200).send(outBuffer);
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

// POST /flyer-projects/:id/ai-generate-logo  { prompt, iconKeys }
// Logo-specific sibling of /ai-generate above -- same "propose, don't
// auto-save" philosophy, but composes a minimal icon+shape+text logo
// mark instead of a promotional flyer layout, so this is the real
// generative gap the Phase 1 audit flagged ("today's AI generation is
// parametric fill-in of 7 fixed templates, not AI-driven layout") --
// the output is genuinely editable canvas_json, the same document model
// every other Logo Studio element uses, never a raster image passed off
// as an editable logo (master spec §14). iconKeys is the client's own
// kFlyerIconLibrary key list (same pattern as POST /ai/find-icon), so
// this route never carries its own copy that could drift out of sync.
router.post('/:id/ai-generate-logo', async (req, res) => {
  const tid = tenantId(req);
  const project = await db.prepare('SELECT * FROM flyer_projects WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!project) return res.status(404).json({ error: 'Flyer project not found' });

  const { prompt, iconKeys } = req.body;
  if (!prompt || typeof prompt !== 'string' || !prompt.trim()) {
    return res.status(400).json({ error: 'prompt is required' });
  }
  if (!Array.isArray(iconKeys) || iconKeys.length === 0) {
    return res.status(400).json({ error: 'iconKeys is required' });
  }

  const canvasW = project.canvas_width || 512;
  const canvasH = project.canvas_height || 512;
  const KNOWN_FONTS = ['SpaceGrotesk','Inter','PlayfairDisplay','Lato','Poppins','Roboto','Montserrat','OpenSans'];

  const aiPrompt = `You are a logo designer for an education-admissions consultancy. Design a simple, professional logo mark as a JSON array of elements for a square canvas that is ${canvasW}x${canvasH} pixels.

Brief: "${prompt.trim()}"

Return ONLY a JSON array (no prose, no markdown fences). Each element must be one of:
- Shape (a background mark, e.g. a circle/rounded badge behind the icon): {"type":"shape","x":<number>,"y":<number>,"width":<number>,"height":<number>,"shapeKind":"rect"|"circle","shapeColor":"<#RRGGBB hex>","cornerRadius":<0-100>}
- Icon: {"type":"icon","x":<number>,"y":<number>,"width":<number>,"height":<number>,"iconKey":"<one of ${iconKeys.join(', ')}>","shapeColor":"<#RRGGBB hex>"}
- Text (brand name or initials, short): {"type":"text","x":<number>,"y":<number>,"width":<number>,"height":<number>,"text":"<short brand name or initials, max 24 chars>","fontSize":<12-72>,"fontFamily":"<one of ${KNOWN_FONTS.join(', ')}>","color":"<#RRGGBB hex>","fontWeight":"normal"|"bold","textAlign":"center"}

Rules: 2-4 elements total -- a logo mark is not a flyer, keep it minimal and iconic. All x/y/width/height must fit within the ${canvasW}x${canvasH} canvas (x>=0, y>=0, x+width<=${canvasW}, y+height<=${canvasH}). Use at most 2 colors total for a cohesive brand mark. Never include rotation. Center the composition.`;

  let rawElements;
  try {
    rawElements = await generateJson(aiPrompt, { maxTokens: 2000 });
  } catch (err) {
    return res.status(502).json({ error: `AI generation failed: ${err.message}` });
  }
  if (!Array.isArray(rawElements)) {
    return res.status(502).json({ error: 'AI returned an unexpected format' });
  }

  const hexRe = /^#[0-9A-Fa-f]{6}$/;
  const iconKeySet = new Set(iconKeys);
  const clampNum = (v, lo, hi, fallback) => {
    const n = Number(v);
    if (!Number.isFinite(n)) return fallback;
    return Math.min(hi, Math.max(lo, n));
  };

  const validated = rawElements
    .filter((el) => el && ['text', 'shape', 'icon'].includes(el.type))
    .slice(0, 8)
    .map((el, i) => {
      const width = clampNum(el.width, 10, canvasW, 100);
      const height = clampNum(el.height, 10, canvasH, 100);
      const x = clampNum(el.x, 0, Math.max(0, canvasW - width), 0);
      const y = clampNum(el.y, 0, Math.max(0, canvasH - height), 0);
      const base = { id: `ai-logo-${Date.now()}-${i}`, type: el.type, x, y, width, height, rotation: 0, zIndex: i };
      if (el.type === 'text') {
        return {
          ...base,
          text: typeof el.text === 'string' ? el.text.slice(0, 24) : 'Brand',
          fontSize: clampNum(el.fontSize, 12, 72, 24),
          fontFamily: KNOWN_FONTS.includes(el.fontFamily) ? el.fontFamily : 'Montserrat',
          color: hexRe.test(el.color) ? el.color : '#1B2A4A',
          fontWeight: el.fontWeight === 'bold' ? 'bold' : 'normal',
          textAlign: 'center',
        };
      }
      if (el.type === 'icon') {
        return {
          ...base,
          iconKey: iconKeySet.has(el.iconKey) ? el.iconKey : iconKeys[0],
          shapeColor: hexRe.test(el.shapeColor) ? el.shapeColor : '#1B2A4A',
        };
      }
      return {
        ...base,
        shapeKind: el.shapeKind === 'circle' ? 'circle' : 'rect',
        shapeColor: hexRe.test(el.shapeColor) ? el.shapeColor : '#F2F2F2',
        cornerRadius: clampNum(el.cornerRadius, 0, 100, 0),
      };
    });

  if (validated.length === 0) {
    return res.status(502).json({ error: 'AI returned no usable elements' });
  }

  res.json({ canvas_json: validated });
});

// POST /flyer-projects/:id/share-link  { lead_id }
// Turns a finished flyer into something that can be sent to one specific
// person in one tap.
//
// The OS share sheet already works, but it costs the counsellor three extra
// steps at the worst possible moment: pick WhatsApp, search the contact,
// pick the right one. The lead's number is already in the CRM, so the app
// can open that exact chat directly.
//
// Sends a link rather than the image bytes because wa.me cannot attach
// media -- so the signed URL is deliberately long-lived (7 days) instead of
// the 5 minutes used for internal document reads. The trade-off is
// conscious: this URL is going to a prospective student who may open it
// hours later on a patchy connection, and it only ever exposes a marketing
// flyer the consultancy is actively trying to publicise -- not a document,
// a recording, or anything about the lead.
router.post('/:id/share-link', async (req, res) => {
  const tid = tenantId(req);
  const project = await db.prepare('SELECT * FROM flyer_projects WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!project) return res.status(404).json({ error: 'Flyer project not found' });

  if (!project.rendered_image_path) {
    return res.status(400).json({ error: 'Render the flyer before sharing it' });
  }

  const SEVEN_DAYS = 7 * 24 * 60 * 60;
  let imageUrl;
  try {
    imageUrl = await getSignedUrl(project.rendered_image_path, SEVEN_DAYS);
  } catch (err) {
    return res.status(502).json({ error: `Could not create share link: ${err.message}` });
  }

  const leadId = req.body.lead_id || project.lead_id;
  if (!leadId) {
    // No lead attached: still useful as a copyable link for a broadcast or
    // a status post, just without the direct-chat shortcut.
    return res.json({ image_url: imageUrl, whatsapp_link: null, lead_id: null });
  }

  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  if (!lead.phone) {
    return res.json({
      image_url: imageUrl,
      whatsapp_link: null,
      lead_id: lead.id,
      lead_name: lead.full_name,
      warning: 'This lead has no phone number on file',
    });
  }

  const tenant = await db.prepare('SELECT default_country_code FROM tenants WHERE id = ?').get(tid);
  const greeting = (req.body.message && String(req.body.message).trim())
    || `Hi ${lead.full_name || 'there'}, sharing this with you.`;
  // Link on its own line: WhatsApp renders a preview for a trailing URL,
  // and the greeting stays readable instead of being buried mid-sentence.
  const message = `${greeting}\n\n${imageUrl}`;

  const link = buildWhatsAppLink(
    lead.phone,
    lead.phone_country_code,
    message,
    tenant && tenant.default_country_code,
  );

  res.json({
    image_url: imageUrl,
    whatsapp_link: link,
    message,
    lead_id: lead.id,
    lead_name: lead.full_name,
    expires_in_days: 7,
  });
});

// POST /flyer-projects/:id/confirm-sent  { lead_id, message }
// wa.me has no delivery callback, so the app confirms the hand-off itself.
// Without this the flyer would never appear in the lead's communication
// history, and the counsellor would have no record of what was sent when.
router.post('/:id/confirm-sent', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, message, created_by } = req.body;
  if (!lead_id) return res.status(400).json({ error: 'lead_id is required' });

  const project = await db.prepare('SELECT title FROM flyer_projects WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!project) return res.status(404).json({ error: 'Flyer project not found' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO communications (id, tenant_id, lead_id, channel, direction, body, created_by)
    VALUES (?, ?, ?, 'whatsapp-link', 'outbound', ?, ?)
  `).run(id, tid, lead_id, message || `Sent flyer: ${project.title || 'Untitled'}`, created_by || null);

  res.status(201).json(await db.prepare('SELECT * FROM communications WHERE id = ?').get(id));
});

// DELETE /flyer-projects/:id
router.delete('/:id', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare('DELETE FROM flyer_projects WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Flyer project not found' });
  res.status(200).json({ deleted: true });
});

module.exports = router;
