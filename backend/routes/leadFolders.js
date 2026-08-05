// backend/routes/leadFolders.js
// Lead Folders — granular source categorization + folder-browse.
//
// Deliberately a NEW, self-contained file (composition, not a blind edit
// of leads.js which this session hasn't freshly verified live). Works
// against the EXISTING leads.source_category column (added in Phase 1
// migration, plain TEXT, no CHECK constraint) — no new migration needed.

const express = require('express');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// Canonical categories with display labels + icon hints for the mobile
// folder tiles. Any OTHER string value already in the DB (from before
// this taxonomy existed) still shows up under "Other" rather than being
// hidden — nothing silently disappears.
const CATEGORY_META = {
  direct: { label: 'Direct Inquiry', icon: 'person' },
  company_forwarded: { label: 'Company Forwarded', icon: 'business' },
  saved_contact: { label: 'Saved Contacts', icon: 'contacts' },
  website_form: { label: 'Website / Capture Form', icon: 'language' },
  lead_ads: { label: 'Facebook / Google Ads', icon: 'campaign' },
  partner_referral: { label: 'Partner Referral', icon: 'handshake' },
  associate_referral: { label: 'Associate Referral', icon: 'group' },
  parent_referral: { label: 'Parent Referral', icon: 'family_restroom' },
  student_referral: { label: 'Student Referral', icon: 'school' },
  social: { label: 'Social Media (organic)', icon: 'share' },
  other: { label: 'Other', icon: 'folder' },
};
const VALID_CATEGORIES = Object.keys(CATEGORY_META);

// GET /leads-folders — every folder with its live lead count
router.get('/', async (req, res) => {
  const tid = tenantId(req);
  const rows = await db.prepare(
    'SELECT source_category, COUNT(*) as count FROM leads WHERE tenant_id = ? GROUP BY source_category'
  ).all(tid);

  const counts = {};
  for (const r of rows) counts[r.source_category || 'other'] = Number(r.count);

  const folders = VALID_CATEGORIES.map((id) => ({
    id,
    label: CATEGORY_META[id].label,
    icon: CATEGORY_META[id].icon,
    count: counts[id] || 0,
  }));

  // Anything in the DB that isn't a known category (legacy/free-text
  // values) gets folded into a synthetic "Uncategorized" bucket so the
  // total always reconciles — nothing silently vanishes from view.
  const knownCount = folders.reduce((s, f) => s + f.count, 0);
  const totalRows = rows.reduce((s, r) => s + Number(r.count), 0);
  if (totalRows > knownCount) {
    folders.push({ id: 'uncategorized', label: 'Uncategorized', icon: 'help_outline', count: totalRows - knownCount });
  }

  res.json({ folders, categories_reference: CATEGORY_META });
});

// GET /leads-folders/:category/leads — leads inside one folder
router.get('/:category/leads', async (req, res) => {
  const tid = tenantId(req);
  const { category } = req.params;

  let rows;
  if (category === 'uncategorized') {
    const placeholders = VALID_CATEGORIES.map(() => '?').join(',');
    rows = await db.prepare(
      `SELECT * FROM leads WHERE tenant_id = ? AND (source_category IS NULL OR source_category NOT IN (${placeholders})) ORDER BY created_at DESC LIMIT 200`
    ).all(tid, ...VALID_CATEGORIES);
  } else {
    rows = await db.prepare(
      'SELECT * FROM leads WHERE tenant_id = ? AND source_category = ? ORDER BY created_at DESC LIMIT 200'
    ).all(tid, category);
  }
  res.json(rows);
});

// PATCH /leads-folders/:leadId  { category }
router.patch('/:leadId', async (req, res) => {
  const tid = tenantId(req);
  const { category } = req.body;
  if (!VALID_CATEGORIES.includes(category)) {
    return res.status(400).json({ error: `category must be one of: ${VALID_CATEGORIES.join(', ')}` });
  }
  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  await db.prepare('UPDATE leads SET source_category = ? WHERE tenant_id = ? AND id = ?').run(category, tid, req.params.leadId);
  res.json({ ok: true, category });
});

module.exports = router;
