// backend/services/logoTemplates.js
// Phase 1 of the AI Logo Generator -- template/parametric approach.
// v2: genuine visual craft pass after Vinay rated v1 0.5/10 with a real
// screenshot showing a plain "WRC" wordmark with just a thin underline --
// that critique was correct, this is the fix. Still pure-string SVG
// (zero native deps, same pattern as flyerTemplates.js), rasterized via
// sharp in routes/tenantLogos.js. Canvas stays transparent (no
// background rect) since a logo composites onto other designs.
//
// Design techniques used, all chosen for being reliably supported by
// librsvg (the SVG engine sharp uses under the hood) rather than newer
// CSS filter features that may not render consistently across
// environments:
//   - Gradients: <linearGradient>/<radialGradient> defs, universally
//     supported, gives shapes real depth instead of flat single colours.
//   - Shadows: a duplicated, offset, semi-transparent dark shape drawn
//     BEHIND the real shape -- the same reliable manual-shadow technique
//     glass_widgets.dart's wrapWithHardShadow() already uses elsewhere in
//     this codebase, deliberately not relying on feDropShadow (patchy
//     librsvg support).
//   - A darken() helper for gradient stops and shadow tone, since
//     "accent_color" alone isn't always dark enough to read as a shadow.

const DEFAULT_FONT = 'Space Grotesk';

function escapeXml(str) {
  return String(str || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// Places text along a circular arc, one character at a time, each with
// its own rotation -- deliberately NOT using SVG <textPath>, which was
// tested against this exact librsvg build (the same engine `sharp`
// uses in routes/tenantLogos.js) and silently rendered nothing: the
// path itself drew fine, but text-on-a-path did not, with no error.
// Manual per-character positioning has no such dependency -- it's
// plain <text> + rotate(), supported everywhere SVG is.
function archText(cx, cy, r, text, { fontSize = 34, fill = '#ffffff', fontFamily = DEFAULT_FONT, spanDegrees = 150 } = {}) {
  const chars = String(text || '').split('');
  const n = chars.length;
  if (n === 0) return '';
  const startAngle = -spanDegrees / 2;
  const step = n > 1 ? spanDegrees / (n - 1) : 0;
  return chars
    .map((ch, i) => {
      const angle = startAngle + step * i; // degrees, 0 = top (12 o'clock), clockwise positive
      const rad = (angle * Math.PI) / 180;
      const x = cx + r * Math.sin(rad);
      const y = cy - r * Math.cos(rad);
      return `<text x="${x.toFixed(2)}" y="${y.toFixed(2)}" font-family="${fontFamily}" font-size="${fontSize}" font-weight="700" fill="${fill}" text-anchor="middle" transform="rotate(${angle.toFixed(2)} ${x.toFixed(2)} ${y.toFixed(2)})">${escapeXml(ch)}</text>`;
    })
    .join('\n    ');
}

function darken(hex, amount) {
  let h = String(hex || '#1B2A4A').replace('#', '');
  if (h.length === 3) h = h.split('').map((c) => c + c).join('');
  const num = parseInt(h, 16);
  if (Number.isNaN(num)) return '#0F1A30';
  let r = (num >> 16) & 0xff;
  let g = (num >> 8) & 0xff;
  let b = num & 0xff;
  r = Math.round(r * (1 - amount));
  g = Math.round(g * (1 - amount));
  b = Math.round(b * (1 - amount));
  return '#' + [r, g, b].map((v) => v.toString(16).padStart(2, '0')).join('');
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
      const primaryDark = darken(primary, 0.35);
      const shadowColor = darken(primary, 0.55);
      const r = ICON_CENTER - 10;
      return `<svg xmlns="http://www.w3.org/2000/svg" width="${ICON_SIZE}" height="${ICON_SIZE}" viewBox="0 0 ${ICON_SIZE} ${ICON_SIZE}">
  <defs>
    <linearGradient id="badgeGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${primary}"/>
      <stop offset="100%" stop-color="${primaryDark}"/>
    </linearGradient>
  </defs>
  <circle cx="${ICON_CENTER}" cy="${ICON_CENTER + 10}" r="${r}" fill="${shadowColor}" opacity="0.35"/>
  <circle cx="${ICON_CENTER}" cy="${ICON_CENTER}" r="${r}" fill="url(#badgeGrad)"/>
  <circle cx="${ICON_CENTER}" cy="${ICON_CENTER}" r="${r - 14}" fill="none" stroke="${accent}" stroke-width="3" opacity="0.55"/>
  <text x="${ICON_CENTER}" y="${ICON_CENTER + 40}" text-anchor="middle" font-family="${f.font_family || DEFAULT_FONT}" font-size="168" font-weight="700" letter-spacing="4" fill="#ffffff">${initials}</text>
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
  <defs>
    <linearGradient id="underlineGrad" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="${accent}"/>
      <stop offset="100%" stop-color="${accent}" stop-opacity="0.15"/>
    </linearGradient>
  </defs>
  <rect x="42" y="88" width="16" height="72" rx="4" fill="${accent}"/>
  <text x="76" y="150" font-family="${f.font_family || DEFAULT_FONT}" font-size="92" font-weight="700" letter-spacing="1.5" fill="${primary}">${name}</text>
  <rect x="44" y="192" width="420" height="7" rx="3.5" fill="url(#underlineGrad)"/>
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
      const primaryDark = darken(primary, 0.35);
      const shadowColor = darken(primary, 0.55);
      const shape = f.icon_shape || 'circle';

      let iconMain;
      let iconShadow;
      if (shape === 'hexagon') {
        iconMain = '<polygon points="70,8 124,39 124,101 70,132 16,101 16,39" fill="url(#iconGrad)"/>';
        iconShadow = '<polygon points="70,16 124,47 124,109 70,140 16,109 16,47" fill="' + shadowColor + '" opacity="0.35"/>';
      } else if (shape === 'diamond') {
        iconMain = '<polygon points="70,6 134,70 70,134 6,70" fill="url(#iconGrad)"/>';
        iconShadow = '<polygon points="70,14 134,78 70,142 6,78" fill="' + shadowColor + '" opacity="0.35"/>';
      } else if (shape === 'square') {
        iconMain = '<rect x="12" y="12" width="116" height="116" rx="24" fill="url(#iconGrad)"/>';
        iconShadow = '<rect x="12" y="20" width="116" height="116" rx="24" fill="' + shadowColor + '" opacity="0.35"/>';
      } else if (shape === 'star') {
        const starPts = '70,4 86,50 134,50 96,78 110,126 70,98 30,126 44,78 6,50 54,50';
        iconMain = `<polygon points="${starPts}" fill="url(#iconGrad)"/>`;
        iconShadow = `<polygon points="${starPts}" fill="${shadowColor}" opacity="0.35" transform="translate(0,8)"/>`;
      } else if (shape === 'shield') {
        const shieldPath = 'M70,6 L126,26 L126,68 Q126,110 70,136 Q14,110 14,68 L14,26 Z';
        iconMain = `<path d="${shieldPath}" fill="url(#iconGrad)"/>`;
        iconShadow = `<path d="${shieldPath}" fill="${shadowColor}" opacity="0.35" transform="translate(0,8)"/>`;
      } else {
        iconMain = '<circle cx="70" cy="70" r="62" fill="url(#iconGrad)"/>';
        iconShadow = '<circle cx="70" cy="78" r="62" fill="' + shadowColor + '" opacity="0.35"/>';
      }

      return `<svg xmlns="http://www.w3.org/2000/svg" width="${WIDE_W}" height="${WIDE_H}" viewBox="0 0 ${WIDE_W} ${WIDE_H}">
  <defs>
    <linearGradient id="iconGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${primary}"/>
      <stop offset="100%" stop-color="${primaryDark}"/>
    </linearGradient>
  </defs>
  <g transform="translate(0, 84)">${iconShadow}${iconMain}</g>
  <text x="180" y="150" font-family="${f.font_family || DEFAULT_FONT}" font-size="78" font-weight="700" letter-spacing="1" fill="${primary}">${name}</text>
</svg>`;
    },
  },

  // v3 (Batch 6, "logo maker complete ecosystem") -- four new templates
  // covering visual territory the original three didn't: an academic/
  // official seal look (crest_seal, arch_badge -- a natural fit for an
  // education consultancy's own branding), a shield emblem, and an
  // abstract icon-only mark for contexts needing a symbol with no text
  // (app icon, favicon, watermark).
  crest_seal: {
    name: 'Crest Seal',
    fields: ['brand_name', 'initials', 'primary_color', 'accent_color', 'font_family'],
    render(f) {
      const initials = escapeXml((f.initials || (f.brand_name || 'LF').slice(0, 2)).toUpperCase());
      const primary = f.primary_color || '#1B2A4A';
      const accent = f.accent_color || primary;
      const primaryDark = darken(primary, 0.35);
      const shadowColor = darken(primary, 0.55);
      return `<svg xmlns="http://www.w3.org/2000/svg" width="${ICON_SIZE}" height="${ICON_SIZE}" viewBox="0 0 ${ICON_SIZE} ${ICON_SIZE}">
  <defs>
    <linearGradient id="crestGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${primary}"/>
      <stop offset="100%" stop-color="${primaryDark}"/>
    </linearGradient>
  </defs>
  <circle cx="${ICON_CENTER}" cy="${ICON_CENTER + 10}" r="${ICON_CENTER - 10}" fill="${shadowColor}" opacity="0.3"/>
  <circle cx="${ICON_CENTER}" cy="${ICON_CENTER}" r="${ICON_CENTER - 10}" fill="url(#crestGrad)"/>
  <circle cx="${ICON_CENTER}" cy="${ICON_CENTER}" r="${ICON_CENTER - 34}" fill="none" stroke="${accent}" stroke-width="4"/>
  <circle cx="${ICON_CENTER}" cy="${ICON_CENTER}" r="${ICON_CENTER - 46}" fill="none" stroke="${accent}" stroke-width="1.5" opacity="0.6"/>
  <text x="${ICON_CENTER}" y="${ICON_CENTER + 36}" text-anchor="middle" font-family="${f.font_family || DEFAULT_FONT}" font-size="140" font-weight="700" letter-spacing="2" fill="#ffffff">${initials}</text>
  <path d="M ${ICON_CENTER - 60} ${ICON_CENTER + 90} L ${ICON_CENTER} ${ICON_CENTER + 116} L ${ICON_CENTER + 60} ${ICON_CENTER + 90}" fill="none" stroke="${accent}" stroke-width="4" stroke-linecap="round"/>
</svg>`;
    },
  },
  shield_emblem: {
    name: 'Shield Emblem',
    fields: ['brand_name', 'initials', 'primary_color', 'accent_color', 'font_family'],
    render(f) {
      const initials = escapeXml((f.initials || (f.brand_name || 'LF').slice(0, 2)).toUpperCase());
      const primary = f.primary_color || '#1B2A4A';
      const accent = f.accent_color || primary;
      const primaryDark = darken(primary, 0.35);
      const shadowColor = darken(primary, 0.55);
      const shieldPath = `M${ICON_CENTER},44 L${ICON_SIZE - 72},110 L${ICON_SIZE - 72},290 Q${ICON_SIZE - 72},420 ${ICON_CENTER},472 Q72,420 72,290 L72,110 Z`;
      const shieldPathShadow = `M${ICON_CENTER},60 L${ICON_SIZE - 72},126 L${ICON_SIZE - 72},306 Q${ICON_SIZE - 72},436 ${ICON_CENTER},488 Q72,436 72,306 L72,126 Z`;
      return `<svg xmlns="http://www.w3.org/2000/svg" width="${ICON_SIZE}" height="${ICON_SIZE}" viewBox="0 0 ${ICON_SIZE} ${ICON_SIZE}">
  <defs>
    <linearGradient id="shieldGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${primary}"/>
      <stop offset="100%" stop-color="${primaryDark}"/>
    </linearGradient>
  </defs>
  <path d="${shieldPathShadow}" fill="${shadowColor}" opacity="0.3"/>
  <path d="${shieldPath}" fill="url(#shieldGrad)"/>
  <path d="${shieldPath}" fill="none" stroke="${accent}" stroke-width="5" opacity="0.7"/>
  <text x="${ICON_CENTER}" y="${ICON_CENTER + 30}" text-anchor="middle" font-family="${f.font_family || DEFAULT_FONT}" font-size="150" font-weight="700" letter-spacing="2" fill="#ffffff">${initials}</text>
</svg>`;
    },
  },
  arch_badge: {
    name: 'Arch Badge',
    fields: ['brand_name', 'initials', 'primary_color', 'accent_color', 'font_family'],
    render(f) {
      // Raw (un-escaped) name -- archText() escapes each character
      // itself, so escaping here first would double-escape entities.
      const rawName = (f.brand_name || 'BRAND NAME').toUpperCase();
      const initials = escapeXml((f.initials || (f.brand_name || 'LF').slice(0, 2)).toUpperCase());
      const primary = f.primary_color || '#1B2A4A';
      const accent = f.accent_color || primary;
      const primaryDark = darken(primary, 0.35);
      const shadowColor = darken(primary, 0.55);
      const r = ICON_CENTER - 10;
      const arcR = ICON_CENTER - 40;
      const arcTextSvg = archText(ICON_CENTER, ICON_CENTER, arcR, rawName, {
        fontSize: rawName.length > 18 ? 24 : 30,
        fontFamily: f.font_family || DEFAULT_FONT,
        spanDegrees: Math.min(200, 60 + rawName.length * 8),
      });
      return `<svg xmlns="http://www.w3.org/2000/svg" width="${ICON_SIZE}" height="${ICON_SIZE}" viewBox="0 0 ${ICON_SIZE} ${ICON_SIZE}">
  <defs>
    <linearGradient id="archGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${primary}"/>
      <stop offset="100%" stop-color="${primaryDark}"/>
    </linearGradient>
  </defs>
  <circle cx="${ICON_CENTER}" cy="${ICON_CENTER + 10}" r="${r}" fill="${shadowColor}" opacity="0.3"/>
  <circle cx="${ICON_CENTER}" cy="${ICON_CENTER}" r="${r}" fill="url(#archGrad)"/>
  <circle cx="${ICON_CENTER}" cy="${ICON_CENTER}" r="${r - 16}" fill="none" stroke="${accent}" stroke-width="2" opacity="0.6"/>
  ${arcTextSvg}
  <text x="${ICON_CENTER}" y="${ICON_CENTER + 40}" text-anchor="middle" font-family="${f.font_family || DEFAULT_FONT}" font-size="120" font-weight="700" fill="#ffffff">${initials}</text>
</svg>`;
    },
  },
  geometric_mark: {
    name: 'Geometric Mark',
    fields: ['primary_color', 'accent_color'],
    render(f) {
      const primary = f.primary_color || '#1B2A4A';
      const accent = f.accent_color || '#E8A33D';
      return `<svg xmlns="http://www.w3.org/2000/svg" width="${ICON_SIZE}" height="${ICON_SIZE}" viewBox="0 0 ${ICON_SIZE} ${ICON_SIZE}">
  <defs>
    <linearGradient id="markGradA" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${primary}"/>
      <stop offset="100%" stop-color="${darken(primary, 0.3)}"/>
    </linearGradient>
    <linearGradient id="markGradB" x1="0%" y1="100%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="${accent}"/>
      <stop offset="100%" stop-color="${darken(accent, 0.15)}"/>
    </linearGradient>
  </defs>
  <polygon points="${ICON_CENTER},52 ${ICON_SIZE - 90},370 90,370" fill="url(#markGradA)" opacity="0.92"/>
  <circle cx="${ICON_SIZE - 150}" cy="${ICON_CENTER + 40}" r="120" fill="url(#markGradB)" opacity="0.85"/>
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

module.exports = { listTemplates, renderLogoTemplate, darken };
