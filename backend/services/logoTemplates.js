// backend/services/logoTemplates.js
// Phase 1 of the AI Logo Generator -- Vinay's explicit choice was the
// zero-cost template/parametric approach first, with real image-gen API
// integration deferred to Phase 2 (logged in Notion). Same pure-string
// SVG generation as flyerTemplates.js -- zero native deps, rasterized
// separately via sharp in routes/tenantLogos.js.
//
// Honest scope: these are parametric shape+typography compositions, not
// generative art -- "Create a premium medical logo" style free-text
// prompts aren't supported yet; the person picks a template + fields.
// Canvas is always transparent (no background rect) since a logo is
// meant to be composited onto other designs, unlike a flyer's filled
// canvas.

const DEFAULT_FONT = 'Space Grotesk';

function escapeXml(str) {
  return String(str || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

const ICON_SIZE = 512;
const ICON_CENTER = ICON_SIZE / 2;
const WIDE_W = 1024;
const WIDE_H = 307;

const TEMPLATES = {
  monogram_badge: {
    name: 'Monogram Badge',
    fields: ['brand_name', 'initials', 'primary_color', 'accent_color', 'font_family'],
    render(f) {
      const initials = escapeXml((f.initials || (f.brand_name || 'LF').slice(0, 2)).toUpperCase());
      const primary = f.primary_color || '#1B2A4A';
      const accent = f.accent_color || primary;
      return `<svg xmlns="http://www.w3.org/2000/svg" width="${ICON_SIZE}" height="${ICON_SIZE}" viewBox="0 0 ${ICON_SIZE} ${ICON_SIZE}">
  <circle cx="${ICON_CENTER}" cy="${ICON_CENTER}" r="${ICON_CENTER - 8}" fill="${primary}"/>
  <circle cx="${ICON_CENTER}" cy="${ICON_CENTER}" r="${ICON_CENTER - 8}" fill="none" stroke="${accent}" stroke-width="6" opacity="0.6"/>
  <text x="${ICON_CENTER}" y="${ICON_CENTER + 42}" text-anchor="middle" font-family="${f.font_family || DEFAULT_FONT}" font-size="180" font-weight="bold" fill="#ffffff">${initials}</text>
</svg>`;
    },
  },
  wordmark: {
    name: 'Wordmark',
    fields: ['brand_name', 'primary_color', 'accent_color', 'font_family'],
    render(f) {
      const name = escapeXml(f.brand_name || 'Brand Name');
      const primary = f.primary_color || '#1B2A4A';
      const accent = f.accent_color || primary;
      return `<svg xmlns="http://www.w3.org/2000/svg" width="${WIDE_W}" height="${WIDE_H}" viewBox="0 0 ${WIDE_W} ${WIDE_H}">
  <text x="40" y="150" font-family="${f.font_family || DEFAULT_FONT}" font-size="88" font-weight="bold" fill="${primary}">${name}</text>
  <rect x="42" y="180" width="180" height="8" rx="4" fill="${accent}"/>
</svg>`;
    },
  },
  icon_text: {
    name: 'Icon + Text',
    fields: ['brand_name', 'primary_color', 'accent_color', 'font_family', 'icon_shape'],
    render(f) {
      const name = escapeXml(f.brand_name || 'Brand Name');
      const primary = f.primary_color || '#1B2A4A';
      const accent = f.accent_color || primary;
      const shape = f.icon_shape || 'circle';
      let iconSvg;
      if (shape === 'hexagon') {
        iconSvg = '<polygon points="70,10 120,40 120,100 70,130 20,100 20,40" fill="' + primary + '"/>';
      } else if (shape === 'diamond') {
        iconSvg = '<polygon points="70,10 130,70 70,130 10,70" fill="' + primary + '"/>';
      } else if (shape === 'square') {
        iconSvg = '<rect x="15" y="15" width="110" height="110" rx="20" fill="' + primary + '"/>';
      } else {
        iconSvg = '<circle cx="70" cy="70" r="60" fill="' + primary + '"/>';
      }
      return `<svg xmlns="http://www.w3.org/2000/svg" width="${WIDE_W}" height="${WIDE_H}" viewBox="0 0 ${WIDE_W} ${WIDE_H}">
  <g transform="translate(0, 84)">${iconSvg}</g>
  <text x="160" y="150" font-family="${f.font_family || DEFAULT_FONT}" font-size="80" font-weight="bold" fill="${accent}">${name}</text>
</svg>`;
    },
  },
};

function listTemplates() {
  return Object.entries(TEMPLATES).map(([id, t]) => ({ id, name: t.name, fields: t.fields }));
}

function renderLogoTemplate(templateId, fields) {
  const tpl = TEMPLATES[templateId];
  if (!tpl) throw new Error(`Unknown logo template_id "${templateId}". Available: ${Object.keys(TEMPLATES).join(', ')}`);
  return tpl.render(fields || {});
}

module.exports = { listTemplates, renderLogoTemplate };
