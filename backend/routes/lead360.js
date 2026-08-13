const express = require('express');
const { buildLead360 } = require('../services/lead360');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /lead360/:leadId — the single cross-module "everything about this
// lead" report: score, prioritized alerts from every department, and one
// AI-synthesized narrative + recommended action. This is the read model
// for the Lead Detail screen's hero panel.
router.get('/:leadId', async (req, res) => {
  const tid = tenantId(req);
  try {
    const report = await buildLead360(tid, req.params.leadId);
    if (!report) return res.status(404).json({ error: 'Lead not found' });
    res.json(report);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
