// Exam Intelligence — Academic Risk Analysis (student-wise + batch-wise).
// Mounted at /exams/analysis. See services/examIntelligence.js for the
// ground rules: deterministic risk score first (SQL-computed, never an AI
// guess, blocks with a clear reason when there isn't enough data), then one
// AI call to narrate the computed numbers, grounded-or-fallback exactly like
// the report card narrative already works.

const express = require('express');
const db = require('../db');
const {
  computeStudentRisk,
  recordStudentRisk,
  generateStudentRiskInsight,
  computeBatchAnalysis,
  generateBatchInsight,
} = require('../services/examIntelligence');

const router = express.Router();

function tenantId(req) {
  return req.user?.tenantId || req.header('x-tenant-id') || 'demo-consultancy';
}

// Same rule as exams.js's canAccessStudent -- duplicated locally rather than
// shared, matching this codebase's existing convention of each route file
// keeping its own small tenant/access-scoping helpers.
async function canAccessStudent(req, studentId) {
  const tid = tenantId(req);
  if (!req.user) return false;
  if (['owner', 'admin'].includes(req.user.role)) {
    const row = await db.prepare('SELECT 1 FROM students WHERE id = ? AND tenant_id = ?').get(studentId, tid);
    return !!row;
  }
  const row = await db
    .prepare(
      `SELECT 1 FROM students s JOIN leads l ON l.id = s.lead_id
       WHERE s.id = ? AND s.tenant_id = ? AND l.tenant_id = ? AND l.assigned_to = ?`
    )
    .get(studentId, tid, tid, req.user.id);
  return !!row;
}

async function fetchStudentName(studentId) {
  const row = await db
    .prepare(`SELECT l.full_name FROM students s JOIN leads l ON l.id = s.lead_id WHERE s.id = ?`)
    .get(studentId);
  return row?.full_name || 'This student';
}

// GET /exams/analysis/students/:studentId — trend + risk + one AI insight.
router.get('/students/:studentId', async (req, res) => {
  const tid = tenantId(req);
  const { studentId } = req.params;
  if (!(await canAccessStudent(req, studentId))) {
    return res.status(404).json({ error: 'Student not found' });
  }

  const risk = await computeStudentRisk(tid, studentId);
  if (risk.blocked) return res.status(422).json(risk);

  await recordStudentRisk(tid, studentId, risk);
  const studentName = await fetchStudentName(studentId);
  const { insight, recommendation, isFallback } = await generateStudentRiskInsight(studentName, risk);

  return res.json({
    academicRisk: risk.academicRisk,
    attendanceRisk: risk.attendanceRisk,
    overallRisk: risk.overallRisk,
    confidence: risk.confidence,
    evidence: risk.evidence,
    insight,
    recommendation,
    insightIsFallback: isFallback,
  });
});

// GET /exams/analysis/batch/:batchYear — aggregate stats + one AI summary
// paragraph. owner/admin see the whole batch; every other role sees only
// their own assigned caseload within it (same rule as the cohort endpoint).
router.get('/batch/:batchYear', async (req, res) => {
  const tid = tenantId(req);
  const { batchYear } = req.params;
  const assignedTo = req.user && ['owner', 'admin'].includes(req.user.role) ? undefined : req.user?.id;

  const batch = await computeBatchAnalysis(tid, batchYear, { assignedTo });
  if (batch.blocked) return res.status(422).json(batch);

  const { insight, isFallback } = await generateBatchInsight(batch);
  return res.json({ ...batch, insight, insightIsFallback: isFallback });
});

module.exports = router;
