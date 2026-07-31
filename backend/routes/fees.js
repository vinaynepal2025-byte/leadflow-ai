const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /fees?lead_id=xxx&status=pending
router.get('/', (req, res) => {
  const tid = tenantId(req);
  const { lead_id, status } = req.query;
  let query = 'SELECT * FROM fee_payments WHERE tenant_id = ?';
  const params = [tid];
  if (lead_id) {
    query += ' AND lead_id = ?';
    params.push(lead_id);
  }
  if (status) {
    query += ' AND status = ?';
    params.push(status);
  }
  query += ' ORDER BY due_date ASC';
  res.json(db.prepare(query).all(...params));
});

// GET /fees/summary — tenant-wide totals for the Fee dashboard
router.get('/summary', (req, res) => {
  const tid = tenantId(req);
  const totalDue = db.prepare(
    "SELECT COALESCE(SUM(amount),0) AS t FROM fee_payments WHERE tenant_id = ? AND status IN ('pending','overdue')"
  ).get(tid).t;
  const totalCollected = db.prepare(
    "SELECT COALESCE(SUM(amount),0) AS t FROM fee_payments WHERE tenant_id = ? AND status = 'paid'"
  ).get(tid).t;
  const overdueCount = db.prepare(
    "SELECT COUNT(*) AS c FROM fee_payments WHERE tenant_id = ? AND status = 'pending' AND due_date < date('now')"
  ).get(tid).c;
  res.json({ total_due: totalDue, total_collected: totalCollected, overdue_count: overdueCount });
});

// POST /fees — create an installment/payment record
router.post('/', (req, res) => {
  const tid = tenantId(req);
  const { lead_id, fee_type, amount, due_date, notes } = req.body;
  if (!lead_id || !fee_type || amount === undefined) {
    return res.status(400).json({ error: 'lead_id, fee_type, and amount are required' });
  }
  const lead = db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found for this tenant' });

  const id = randomUUID();
  db.prepare(`
    INSERT INTO fee_payments (id, tenant_id, lead_id, fee_type, amount, due_date, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, fee_type, amount, due_date || null, notes || null);

  res.status(201).json(db.prepare('SELECT * FROM fee_payments WHERE id = ?').get(id));
});

// PATCH /fees/:id  — mark paid, change method, etc.
router.patch('/:id', (req, res) => {
  const tid = tenantId(req);
  const existing = db.prepare('SELECT * FROM fee_payments WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
  if (!existing) return res.status(404).json({ error: 'Payment record not found' });

  const allowed = ['fee_type', 'amount', 'due_date', 'paid_date', 'status', 'payment_method', 'notes'];
  const updates = [];
  const values = [];
  for (const field of allowed) {
    if (req.body[field] !== undefined) {
      updates.push(`${field} = ?`);
      values.push(req.body[field]);
    }
  }
  // Convenience: marking status=paid auto-stamps paid_date if not explicitly given
  if (req.body.status === 'paid' && req.body.paid_date === undefined) {
    updates.push("paid_date = date('now')");
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });

  values.push(tid, req.params.id);
  db.prepare(`UPDATE fee_payments SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  res.json(db.prepare('SELECT * FROM fee_payments WHERE id = ?').get(req.params.id));
});

module.exports = router;
