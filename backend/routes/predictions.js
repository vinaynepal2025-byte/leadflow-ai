const express = require('express');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /predictions/colleges/:leadId — ranks colleges by how good a fit
// they are, using this consultancy's own historical outcomes.
router.get('/colleges/:leadId', async (req, res) => {
  const tid = tenantId(req);
  const lead = await db.prepare('SELECT * FROM leads WHERE tenant_id = ? AND id = ?').get(tid, req.params.leadId);
  if (!lead) return res.status(404).json({ error: 'Lead not found' });

  const colleges = await db.prepare('SELECT * FROM colleges WHERE tenant_id = ?').all(tid);
  if (colleges.length === 0) {
    return res.json({ predictions: [], note: 'Add colleges (College CRM) and record past admission outcomes to enable predictions.' });
  }

  const predictions = await Promise.all(colleges.map(async (college) => {
    const outcomes = await db.prepare(`
      SELECT application_status, COUNT(*) AS c
      FROM admission_applications
      WHERE tenant_id = ? AND institution_name = ?
      GROUP BY application_status
    `).all(tid, college.name);

    const offers = outcomes.filter((o) => ['Offer', 'Accepted'].includes(o.application_status)).reduce((s, o) => s + o.c, 0);
    const rejections = outcomes.filter((o) => o.application_status === 'Rejected').reduce((s, o) => s + o.c, 0);
    const totalDecided = offers + rejections;

    let historicalRate = null;
    let confidence = 'no data';
    if (totalDecided >= 3) {
      historicalRate = Math.round((offers / totalDecided) * 100);
      confidence = totalDecided >= 10 ? 'high' : 'moderate';
    } else if (totalDecided > 0) {
      historicalRate = Math.round((offers / totalDecided) * 100);
      confidence = 'low (few past cases)';
    }

    const fitNotes = [];
    if (college.commission_percent) {
      fitNotes.push(`Consultancy earns ${college.commission_percent}% commission here`);
    }

    return {
      college_id: college.id,
      college_name: college.name,
      country: college.country,
      historical_offer_rate_percent: historicalRate,
      confidence,
      past_offers: offers,
      past_rejections: rejections,
      fit_notes: fitNotes,
    };
  }));

  predictions.sort((a, b) => {
    if (a.historical_offer_rate_percent === null && b.historical_offer_rate_percent === null) return 0;
    if (a.historical_offer_rate_percent === null) return 1;
    if (b.historical_offer_rate_percent === null) return -1;
    return b.historical_offer_rate_percent - a.historical_offer_rate_percent;
  });

  res.json({ lead_id: lead.id, predictions });
});

// GET /predictions/insights — tenant-wide: which colleges are converting
router.get('/insights', async (req, res) => {
  const tid = tenantId(req);
  const rows = await db.prepare(`
    SELECT institution_name,
           COUNT(*) AS total_applications,
           SUM(CASE WHEN application_status IN ('Offer','Accepted') THEN 1 ELSE 0 END) AS offers,
           SUM(CASE WHEN application_status = 'Rejected' THEN 1 ELSE 0 END) AS rejections
    FROM admission_applications WHERE tenant_id = ?
    GROUP BY institution_name
    HAVING total_applications >= 2
    ORDER BY offers DESC
  `).all(tid);

  res.json(rows.map((r) => ({
    ...r,
    offer_rate_percent: (r.offers + r.rejections) > 0 ? Math.round((r.offers / (r.offers + r.rejections)) * 100) : null,
  })));
});

module.exports = router;
