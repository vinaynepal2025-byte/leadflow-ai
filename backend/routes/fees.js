const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { createReminder } = require('./reminders');
const { createNotification } = require('./notifications');
const { uploadFile } = require('../services/supabaseStorage');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// GET /fees?lead_id=xxx&status=pending
router.get('/', async (req, res) => {
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
  res.json(await db.prepare(query).all(...params));
});

// GET /fees/summary — tenant-wide totals for the Fee dashboard
router.get('/summary', async (req, res) => {
  const tid = tenantId(req);
  const totalDueRow = await db.prepare(
    "SELECT COALESCE(SUM(amount),0) AS t FROM fee_payments WHERE tenant_id = ? AND status IN ('pending','overdue')"
  ).get(tid);
  const totalDue = totalDueRow.t;
  const totalCollectedRow = await db.prepare(
    "SELECT COALESCE(SUM(amount),0) AS t FROM fee_payments WHERE tenant_id = ? AND status = 'paid'"
  ).get(tid);
  const totalCollected = totalCollectedRow.t;
  const overdueCountRow = await db.prepare(
    "SELECT COUNT(*) AS c FROM fee_payments WHERE tenant_id = ? AND status = 'pending' AND due_date::date < CURRENT_DATE"
  ).get(tid);
  const overdueCount = overdueCountRow.c;
  res.json({ total_due: totalDue, total_collected: totalCollected, overdue_count: overdueCount });
});

// Shared by POST / and POST /plan — a fee record with a due date is
// exactly the kind of thing that should show up in Reminders and in
// Lead 360's alert feed without the counselor having to remember to add
// it manually. Best-effort: a reminder failure never blocks fee creation.
async function reminderForFee(tid, feeRow) {
  if (!feeRow.due_date) return;
  try {
    await createReminder(tid, {
      leadId: feeRow.lead_id,
      title: `Fee due: ${feeRow.fee_type} — ₹${feeRow.amount}`,
      dueAt: feeRow.due_date,
    });
  } catch (_) {
    // non-critical
  }
}

// POST /fees — create a single installment/payment record
router.post('/', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, fee_type, amount, due_date, notes } = req.body;
  if (!lead_id || !fee_type || amount === undefined) {
    return res.status(400).json({ error: 'lead_id, fee_type, and amount are required' });
  }
  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found for this tenant' });

  const id = randomUUID();
  await db.prepare(`
    INSERT INTO fee_payments (id, tenant_id, lead_id, fee_type, amount, due_date, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(id, tid, lead_id, fee_type, amount, due_date || null, notes || null);

  const row = await db.prepare('SELECT * FROM fee_payments WHERE id = ?').get(id);
  await reminderForFee(tid, row);
  res.status(201).json(row);
});

// POST /fees/plan — generate an EMI/installment schedule in one call
// instead of the counselor manually creating each installment.
// Body: { lead_id, fee_type, total_amount, num_installments, start_date,
//          frequency: 'monthly' | 'weekly' (default 'monthly'), notes }
router.post('/plan', async (req, res) => {
  const tid = tenantId(req);
  const { lead_id, fee_type, total_amount, num_installments, start_date, frequency, notes } = req.body;

  if (!lead_id || !fee_type || total_amount === undefined || !num_installments || !start_date) {
    return res.status(400).json({
      error: 'lead_id, fee_type, total_amount, num_installments, and start_date are required',
    });
  }
  const n = parseInt(num_installments, 10);
  if (!Number.isInteger(n) || n < 1 || n > 60) {
    return res.status(400).json({ error: 'num_installments must be an integer between 1 and 60' });
  }
  const lead = await db.prepare('SELECT id FROM leads WHERE tenant_id = ? AND id = ?').get(tid, lead_id);
  if (!lead) return res.status(404).json({ error: 'Lead not found for this tenant' });

  const freq = frequency === 'weekly' ? 'weekly' : 'monthly';
  const planId = randomUUID();

  // Split evenly, rounding down each installment and putting the leftover
  // on the LAST installment so the total always reconciles exactly to
  // total_amount (no silent rounding drift across many installments).
  const base = Math.floor((Number(total_amount) / n) * 100) / 100;
  const amounts = Array.from({ length: n }, () => base);
  const roundedSum = amounts.reduce((s, a) => s + a, 0);
  amounts[n - 1] = Math.round((Number(total_amount) - roundedSum + base) * 100) / 100;

  const created = [];
  for (let i = 0; i < n; i++) {
    const due = new Date(start_date);
    if (freq === 'monthly') due.setMonth(due.getMonth() + i);
    else due.setDate(due.getDate() + i * 7);
    const dueDateStr = due.toISOString().slice(0, 10);

    const id = randomUUID();
    await db.prepare(`
      INSERT INTO fee_payments
        (id, tenant_id, lead_id, fee_type, amount, due_date, notes, plan_id, installment_number, total_installments)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(id, tid, lead_id, fee_type, amounts[i], dueDateStr,
      notes || null, planId, i + 1, n);

    const row = await db.prepare('SELECT * FROM fee_payments WHERE id = ?').get(id);
    await reminderForFee(tid, row);
    created.push(row);
  }

  res.status(201).json({ plan_id: planId, installments: created });
});

// Builds a simple, print-friendly HTML receipt and stores it via the same
// Supabase Storage path Documents uses, then links it as a document row
// (doc_type: 'receipt') — reusing existing infra instead of building a
// second file-storage mechanism (composition over addition).
async function generateReceipt(tid, feeRow) {
  const lead = await db.prepare('SELECT full_name FROM leads WHERE tenant_id = ? AND id = ?').get(tid, feeRow.lead_id);
  const tenant = await db.prepare('SELECT * FROM tenants WHERE id = ?').get(tid);
  const receiptNo = `RCPT-${feeRow.id.slice(0, 8).toUpperCase()}`;
  const html = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Receipt ${receiptNo}</title>
<style>
  body { font-family: -apple-system, Arial, sans-serif; max-width: 480px; margin: 24px auto; color: #1B2A4A; }
  h1 { font-size: 18px; border-bottom: 2px solid #1B2A4A; padding-bottom: 8px; }
  table { width: 100%; border-collapse: collapse; margin-top: 16px; }
  td { padding: 6px 0; }
  td:first-child { color: #64748B; }
  td:last-child { text-align: right; font-weight: 600; }
  .total { font-size: 16px; border-top: 1px solid #ccc; margin-top: 8px; padding-top: 8px; }
</style></head>
<body>
  <h1>${tenant?.name || 'LeadFlow AI'} — Payment Receipt</h1>
  <table>
    <tr><td>Receipt No.</td><td>${receiptNo}</td></tr>
    <tr><td>Student</td><td>${lead?.full_name || ''}</td></tr>
    <tr><td>Fee Type</td><td>${feeRow.fee_type}</td></tr>
    <tr><td>Payment Method</td><td>${feeRow.payment_method || 'Not specified'}</td></tr>
    <tr><td>Paid On</td><td>${feeRow.paid_date || ''}</td></tr>
    <tr class="total"><td>Amount Paid</td><td>₹${feeRow.amount}</td></tr>
  </table>
</body></html>`;

  const storagePath = `receipts/${feeRow.id}-${receiptNo}.html`;
  await uploadFile(Buffer.from(html, 'utf-8'), storagePath, 'text/html');

  const docId = randomUUID();
  await db.prepare(`
    INSERT INTO documents (id, tenant_id, lead_id, doc_type, file_name, stored_path, uploaded_by, status)
    VALUES (?, ?, ?, 'receipt', ?, ?, 'system', 'verified')
  `).run(docId, tid, feeRow.lead_id, `${receiptNo}.html`, storagePath);

  return docId;
}

// PATCH /fees/:id  — mark paid, change method, etc.
router.patch('/:id', async (req, res) => {
  const tid = tenantId(req);
  const existing = await db.prepare('SELECT * FROM fee_payments WHERE tenant_id = ? AND id = ?').get(tid, req.params.id);
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
  const justMarkedPaid = req.body.status === 'paid' && existing.status !== 'paid';
  // Convenience: marking status=paid auto-stamps paid_date if not explicitly given
  if (justMarkedPaid && req.body.paid_date === undefined) {
    updates.push("paid_date = date('now')");
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No valid fields to update' });

  values.push(tid, req.params.id);
  await db.prepare(`UPDATE fee_payments SET ${updates.join(', ')} WHERE tenant_id = ? AND id = ?`).run(...values);
  const row = await db.prepare('SELECT * FROM fee_payments WHERE id = ?').get(req.params.id);

  let receiptDocId = null;
  if (justMarkedPaid) {
    try {
      receiptDocId = await generateReceipt(tid, row);
      const lead = await db.prepare('SELECT full_name FROM leads WHERE id = ?').get(row.lead_id);
      await createNotification(tid, {
        title: `Payment received: ₹${row.amount}`,
        body: `${lead?.full_name || 'A lead'} paid ${row.fee_type} — receipt generated`,
        linkType: 'lead',
        linkId: row.lead_id,
      });
    } catch (_) {
      // Receipt generation is a nice-to-have on top of the payment record
      // itself — never fail the payment update because of it.
    }
  }

  res.json({ ...row, receipt_document_id: receiptDocId });
});

// DELETE /fees/:id
router.delete('/:id', async (req, res) => {
  const tid = tenantId(req);
  const result = await db.prepare('DELETE FROM fee_payments WHERE tenant_id = ? AND id = ?').run(tid, req.params.id);
  if (result.changes === 0) return res.status(404).json({ error: 'Payment record not found' });
  res.status(204).send();
});

module.exports = router;
