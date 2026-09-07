// Renders a computed report-card summary (see examIntelligence.js) as a
// PNG image, so it can be sent as the image itself in a WhatsApp message
// rather than a link the parent has to open. Uses `sharp`, already a
// backend dependency (used elsewhere for image processing) — rasterizing
// an SVG string is a normal, supported `sharp` operation, so no new
// dependency (canvas, puppeteer, etc.) was added for this.
//
// Honors a `report_templates.config` object (see examIntelligence.js's
// DEFAULT_TEMPLATE_CONFIG for its shape) rather than a fixed hardcoded
// layout: which sections appear (`fields`), subject display order
// (`subjectOrder`), header colour/title (`branding`), and a closing
// `footerText`/`disclaimer`. The caller is expected to have already merged
// a tenant's chosen template with the default (a field the template
// doesn't specify falls back to the default's value) — this module just
// renders whatever config object it's given.

const sharp = require('sharp');

function escapeXml(str) {
  return String(str).replace(/[<>&'"]/g, (c) => ({
    '<': '&lt;', '>': '&gt;', '&': '&amp;', "'": '&apos;', '"': '&quot;',
  }[c]));
}

function orderedSubjects(summary, subjectOrder) {
  if (!subjectOrder || !subjectOrder.length) return summary.subjects;
  const byName = new Map(summary.subjects.map((s) => [s.subject, s]));
  const ordered = subjectOrder.filter((name) => byName.has(name)).map((name) => byName.get(name));
  // Any subject not mentioned in the template's explicit order still
  // appears (appended), so a newly-added subject is never silently hidden
  // just because an older template predates it.
  const remaining = summary.subjects.filter((s) => !subjectOrder.includes(s.subject));
  return [...ordered, ...remaining];
}

/// `summary` is the object returned by examIntelligence.computeReportCard().
/// `studentMeta` may include studentCode/batch/course — shown only for the
/// fields actually provided, never inventing a placeholder. Returns a PNG
/// buffer.
async function renderReportCardPng(summary, { studentName, tenantName, narrative, template = {}, studentMeta = {} }) {
  const fields = template.fields || ['subjects', 'total', 'rank', 'batchAverage', 'previousDelta', 'narrative'];
  const has = (f) => fields.includes(f);
  const subjects = has('subjects') ? orderedSubjects(summary, template.subjectOrder) : [];
  const headerColor = (template.branding && template.branding.headerColor) || '#1e3a8a';
  const title = (template.branding && template.branding.title) || tenantName || 'Report Card';

  const metaLine = [studentMeta.studentCode, studentMeta.batch, studentMeta.course].filter(Boolean).join(' · ');

  const rowHeight = 34;
  const headerHeight = metaLine ? 190 : 170;
  const tableHeaderHeight = subjects.length ? 40 : 0;
  const footerLines =
    (has('narrative') && narrative ? wrapText(narrative, 78) : []).length +
    (template.footerText ? wrapText(template.footerText, 90).length : 0) +
    (template.disclaimer ? wrapText(template.disclaimer, 90).length : 0);
  const footerHeight = footerLines ? footerLines * 20 + 40 : 20;
  const width = 720;
  const height = headerHeight + tableHeaderHeight + subjects.length * rowHeight + 90 + footerHeight;

  const subjectRows = subjects
    .map((s, i) => {
      const y = headerHeight + tableHeaderHeight + i * rowHeight;
      const marksText = s.marksObtained === null ? 'N/A' : `${s.marksObtained} / ${s.maxMarks}`;
      const pctText = s.percentage === null ? '' : `${s.percentage}%`;
      return `
        <rect x="32" y="${y}" width="${width - 64}" height="${rowHeight}" fill="${i % 2 === 0 ? '#f8fafc' : '#ffffff'}"/>
        <text x="48" y="${y + 22}" font-size="16" fill="#1e293b">${escapeXml(s.subject)}</text>
        <text x="${width - 220}" y="${y + 22}" font-size="16" fill="#1e293b" text-anchor="end">${escapeXml(marksText)}</text>
        <text x="${width - 48}" y="${y + 22}" font-size="16" fill="#475569" text-anchor="end">${escapeXml(pctText)}</text>
      `;
    })
    .join('');

  const tableBottom = headerHeight + tableHeaderHeight + subjects.length * rowHeight;
  const deltaText =
    has('previousDelta') && summary.previousDelta
      ? `${summary.previousDelta.change >= 0 ? '▲' : '▼'} ${Math.abs(summary.previousDelta.change)} pts vs ${escapeXml(summary.previousDelta.comparedTo)}`
      : '';
  const batchAverageText = has('batchAverage') && summary.batchAverage !== null ? `Batch average: ${summary.batchAverage}/${summary.maxTotal}` : '';

  let footerY = tableBottom + (has('total') ? 56 : 16);
  const footerBlocks = [];
  if ((batchAverageText || deltaText)) {
    footerBlocks.push(`<text x="32" y="${footerY}" font-size="14" fill="#475569">${[batchAverageText, deltaText].filter(Boolean).join(' · ')}</text>`);
    footerY += 26;
  }
  if (has('narrative') && narrative) {
    const lines = wrapText(narrative, 78);
    footerBlocks.push(
      `<text x="32" y="${footerY}" font-size="14" fill="#334155">${lines
        .map((line, i) => `<tspan x="32" dy="${i === 0 ? 0 : 20}">${escapeXml(line)}</tspan>`)
        .join('')}</text>`
    );
    footerY += lines.length * 20 + 10;
  }
  if (template.footerText) {
    const lines = wrapText(template.footerText, 90);
    footerBlocks.push(
      `<text x="32" y="${footerY}" font-size="12" fill="#64748b">${lines
        .map((line, i) => `<tspan x="32" dy="${i === 0 ? 0 : 16}">${escapeXml(line)}</tspan>`)
        .join('')}</text>`
    );
    footerY += lines.length * 16 + 8;
  }
  if (template.disclaimer) {
    const lines = wrapText(template.disclaimer, 90);
    footerBlocks.push(
      `<text x="32" y="${footerY}" font-size="11" fill="#94a3b8" font-style="italic">${lines
        .map((line, i) => `<tspan x="32" dy="${i === 0 ? 0 : 15}">${escapeXml(line)}</tspan>`)
        .join('')}</text>`
    );
  }

  const totalsBar = has('total')
    ? `<rect x="32" y="${tableBottom}" width="${width - 64}" height="40" fill="${headerColor}"/>
       <text x="48" y="${tableBottom + 26}" font-size="16" fill="#ffffff" font-weight="bold">Total: ${summary.total} / ${summary.maxTotal}</text>
       <text x="${width - 48}" y="${tableBottom + 26}" font-size="16" fill="#ffffff" font-weight="bold" text-anchor="end">${summary.overallPercentage}% — Grade ${summary.overallGrade}</text>`
    : '';

  const svg = `
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <rect width="${width}" height="${height}" fill="#ffffff"/>
      <rect width="${width}" height="110" fill="${headerColor}"/>
      <text x="32" y="46" font-size="22" fill="#ffffff" font-weight="bold">${escapeXml(title)}</text>
      <text x="32" y="76" font-size="16" fill="#dbeafe">${escapeXml(summary.examGroup)}</text>
      <text x="32" y="140" font-size="20" fill="#0f172a" font-weight="bold">${escapeXml(studentName)}</text>
      ${metaLine ? `<text x="32" y="164" font-size="14" fill="#64748b">${escapeXml(metaLine)}</text>` : ''}
      ${has('rank') ? `<text x="${width - 32}" y="140" font-size="16" fill="#334155" text-anchor="end">Rank ${summary.rank} / ${summary.cohortSize}</text>` : ''}
      ${subjectRows}
      ${totalsBar}
      ${footerBlocks.join('\n')}
    </svg>
  `;

  return sharp(Buffer.from(svg)).png().toBuffer();
}

/// Naive word-wrap for the SVG text block (SVG has no built-in wrapping).
function wrapText(text, maxCharsPerLine) {
  const words = String(text).split(/\s+/);
  const lines = [];
  let current = '';
  for (const word of words) {
    if ((current + ' ' + word).trim().length > maxCharsPerLine) {
      lines.push(current.trim());
      current = word;
    } else {
      current = (current + ' ' + word).trim();
    }
  }
  if (current) lines.push(current);
  return lines;
}

module.exports = { renderReportCardPng };
