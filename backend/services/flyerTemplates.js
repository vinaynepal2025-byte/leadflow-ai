// backend/services/flyerTemplates.js
// Pure-string SVG generation — zero native dependencies, zero crash risk.
// Rasterization to PNG happens separately (in routes/flyers.js, via sharp).
//
// Each template is a function: (fields) -> svg string.
// fields always include: org_name, theme_color (both tenant-derived
// defaults, overridable) plus template-specific text fields.

function escapeXml(str) {
  return String(str || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// Wraps text into multiple <tspan> lines so long headlines/offers don't
// overflow the canvas — simple char-count wrap, good enough for flyer copy.
function wrapText(text, maxCharsPerLine) {
  const words = String(text || '').split(' ');
  const lines = [];
  let current = '';
  for (const word of words) {
    if ((current + ' ' + word).trim().length > maxCharsPerLine) {
      if (current) lines.push(current.trim());
      current = word;
    } else {
      current += ' ' + word;
    }
  }
  if (current) lines.push(current.trim());
  return lines;
}

function tspanLines(lines, x, startY, lineHeight) {
  return lines
    .map((line, i) => `<tspan x="${x}" y="${startY + i * lineHeight}">${escapeXml(line)}</tspan>`)
    .join('');
}

const TEMPLATES = {
  offer_announcement: {
    name: 'Offer Announcement',
    fields: ['org_name', 'theme_color', 'headline', 'offer_text', 'subtext', 'contact_line'],
    render(f) {
      const headlineLines = wrapText(f.headline || 'Special Offer', 22);
      const subtextLines = wrapText(f.subtext || '', 34);
      return `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1350" viewBox="0 0 1080 1350">
  <rect width="1080" height="1350" fill="${f.theme_color || '#1B2A4A'}"/>
  <rect x="40" y="40" width="1000" height="1270" fill="none" stroke="#ffffff" stroke-opacity="0.25" stroke-width="2"/>
  <text x="540" y="140" text-anchor="middle" font-family="sans-serif" font-size="34" fill="#ffffff" opacity="0.85">${escapeXml(f.org_name || 'LeadFlow AI')}</text>
  <text x="540" y="380" text-anchor="middle" font-family="sans-serif" font-size="64" font-weight="bold" fill="#ffffff">${tspanLines(headlineLines, 540, 380, 76)}</text>
  <rect x="140" y="600" width="800" height="220" rx="24" fill="#ffffff"/>
  <text x="540" y="700" text-anchor="middle" font-family="sans-serif" font-size="56" font-weight="bold" fill="${f.theme_color || '#1B2A4A'}">${escapeXml(f.offer_text || '')}</text>
  <text x="540" y="950" text-anchor="middle" font-family="sans-serif" font-size="30" fill="#ffffff" opacity="0.9">${tspanLines(subtextLines, 540, 950, 42)}</text>
  <text x="540" y="1250" text-anchor="middle" font-family="sans-serif" font-size="26" fill="#ffffff" opacity="0.7">${escapeXml(f.contact_line || '')}</text>
</svg>`;
    },
  },

  campus_visit_invite: {
    name: 'Campus Visit Invite',
    fields: ['org_name', 'theme_color', 'event_title', 'date_line', 'location_line', 'contact_line'],
    render(f) {
      const titleLines = wrapText(f.event_title || 'Campus Visit', 20);
      return `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1350" viewBox="0 0 1080 1350">
  <rect width="1080" height="1350" fill="#ffffff"/>
  <rect width="1080" height="420" fill="${f.theme_color || '#1B2A4A'}"/>
  <text x="540" y="120" text-anchor="middle" font-family="sans-serif" font-size="30" fill="#ffffff" opacity="0.85">${escapeXml(f.org_name || 'LeadFlow AI')}</text>
  <text x="540" y="260" text-anchor="middle" font-family="sans-serif" font-size="58" font-weight="bold" fill="#ffffff">${tspanLines(titleLines, 540, 260, 70)}</text>
  <text x="540" y="620" text-anchor="middle" font-family="sans-serif" font-size="40" font-weight="bold" fill="${f.theme_color || '#1B2A4A'}">${escapeXml(f.date_line || '')}</text>
  <text x="540" y="700" text-anchor="middle" font-family="sans-serif" font-size="30" fill="#333333">${escapeXml(f.location_line || '')}</text>
  <circle cx="540" cy="950" r="120" fill="${f.theme_color || '#1B2A4A'}" opacity="0.08"/>
  <text x="540" y="965" text-anchor="middle" font-family="sans-serif" font-size="60">🎓</text>
  <text x="540" y="1250" text-anchor="middle" font-family="sans-serif" font-size="26" fill="#555555">${escapeXml(f.contact_line || '')}</text>
</svg>`;
    },
  },

  general_announcement: {
    name: 'General Announcement',
    fields: ['org_name', 'theme_color', 'headline', 'body_text', 'contact_line'],
    render(f) {
      const headlineLines = wrapText(f.headline || '', 20);
      const bodyLines = wrapText(f.body_text || '', 36);
      return `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1350" viewBox="0 0 1080 1350">
  <rect width="1080" height="1350" fill="#f7f8fa"/>
  <rect x="0" y="0" width="1080" height="16" fill="${f.theme_color || '#1B2A4A'}"/>
  <text x="80" y="140" font-family="sans-serif" font-size="28" fill="${f.theme_color || '#1B2A4A'}" font-weight="bold">${escapeXml(f.org_name || 'LeadFlow AI')}</text>
  <text x="80" y="280" font-family="sans-serif" font-size="52" font-weight="bold" fill="#1a1a1a">${tspanLines(headlineLines, 80, 280, 64)}</text>
  <text x="80" y="500" font-family="sans-serif" font-size="30" fill="#444444">${tspanLines(bodyLines, 80, 500, 44)}</text>
  <text x="80" y="1250" font-family="sans-serif" font-size="24" fill="#888888">${escapeXml(f.contact_line || '')}</text>
</svg>`;
    },
  },
};

function listTemplates() {
  return Object.entries(TEMPLATES).map(([id, t]) => ({ id, name: t.name, fields: t.fields }));
}

function renderTemplate(templateId, fields) {
  const template = TEMPLATES[templateId];
  if (!template) throw new Error(`Unknown template: ${templateId}`);
  return template.render(fields);
}

module.exports = { listTemplates, renderTemplate };
