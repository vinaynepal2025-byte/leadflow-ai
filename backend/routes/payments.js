const express = require('express');
const { randomUUID } = require('crypto');
const db = require('../db');
const { createNotification } = require('./notifications');
const {
  createRazorpayOrder, verifyRazorpaySignature,
  buildEsewaPaymentForm,
  initiateKhaltiPayment, verifyKhaltiPayment,
} = require('../services/payments');

const router = express.Router();

function tenantId(req) {
  return req.header('x-tenant-id') || 'demo-consultancy';
}

// POST /payments/initiate  { fee_payment_id, gateway, return_url? }
router.post('/initiate', async (req, res) => {
  const tid = tenantId(req);
  const { fee_payment_id, gateway } = req.body;
  if (!fee_payment_id || !gateway) return res.status(400).json({ error: 'fee_payment_id and gateway are required' });
  if (!['razorpay', 'esewa', 'khalti'].includes(gateway)) {
    return res.status(400).json({ error: 'gateway must be one of: razorpay, esewa, khalti' });
  }

  const fee = db.prepare('SELECT * FROM fee_payments WHERE tenant_id = ? AND id = ?').get(tid, fee_payment_id);
  if (!fee) return res.status(404).json({ error: 'Fee record not found' });
  if (fee.status === 'paid') return res.status(400).json({ error: 'This fee is already marked paid' });

  const linkId = randomUUID();
  const returnUrl = req.body.return_url || `${req.protocol}://${req.get('host')}/payments/callback/${linkId}`;

  try {
    let gatewayResult;
    if (gateway === 'razorpay') {
      gatewayResult = await createRazorpayOrder({ amountInRupees: fee.amount, receiptId: linkId });
      db.prepare(`
        INSERT INTO payment_links (id, tenant_id, fee_payment_id, gateway, gateway_order_id, amount, status)
        VALUES (?, ?, ?, 'razorpay', ?, ?, 'created')
      `).run(linkId, tid, fee_payment_id, gatewayResult.gateway_order_id, fee.amount);
      return res.status(201).json({ link_id: linkId, gateway: 'razorpay', checkout_config: gatewayResult.checkout_config });
    }

    if (gateway === 'esewa') {
      gatewayResult = buildEsewaPaymentForm({
        amountInRupees: fee.amount, transactionId: linkId,
        successUrl: returnUrl, failureUrl: returnUrl,
      });
      db.prepare(`
        INSERT INTO payment_links (id, tenant_id, fee_payment_id, gateway, amount, status)
        VALUES (?, ?, ?, 'esewa', ?, 'created')
      `).run(linkId, tid, fee_payment_id, fee.amount);
      return res.status(201).json({ link_id: linkId, gateway: 'esewa', action_url: gatewayResult.action_url, fields: gatewayResult.fields });
    }

    if (gateway === 'khalti') {
      const lead = db.prepare('SELECT full_name, phone FROM leads WHERE id = ?').get(fee.lead_id);
      gatewayResult = await initiateKhaltiPayment({
        amountInRupees: fee.amount, purchaseOrderId: linkId,
        purchaseOrderName: fee.fee_type, returnUrl, customerPhone: lead?.phone,
      });
      db.prepare(`
        INSERT INTO payment_links (id, tenant_id, fee_payment_id, gateway, gateway_order_id, amount, status, payment_url)
        VALUES (?, ?, ?, 'khalti', ?, ?, 'created', ?)
      `).run(linkId, tid, fee_payment_id, gatewayResult.gateway_order_id, fee.amount, gatewayResult.payment_url);
      return res.status(201).json({ link_id: linkId, gateway: 'khalti', payment_url: gatewayResult.payment_url });
    }
  } catch (err) {
    return res.status(502).json({ error: err.message });
  }
});

function markPaid(tid, link) {
  db.prepare("UPDATE payment_links SET status = 'paid', paid_at = datetime('now') WHERE id = ?").run(link.id);
  db.prepare("UPDATE fee_payments SET status = 'paid', paid_date = date('now'), payment_method = ? WHERE id = ?")
    .run(link.gateway, link.fee_payment_id);

  const fee = db.prepare('SELECT * FROM fee_payments WHERE id = ?').get(link.fee_payment_id);
  const lead = db.prepare('SELECT full_name FROM leads WHERE id = ?').get(fee.lead_id);
  createNotification(tid, {
    title: `Payment received: ${lead?.full_name || 'lead'}`,
    body: `${fee.fee_type} — ₹${link.amount} via ${link.gateway}`,
    linkType: 'lead', linkId: fee.lead_id,
  });
}

// POST /payments/razorpay/verify  { link_id, razorpay_payment_id, razorpay_signature }
router.post('/razorpay/verify', (req, res) => {
  const tid = tenantId(req);
  const { link_id, razorpay_payment_id, razorpay_signature } = req.body;
  const link = db.prepare('SELECT * FROM payment_links WHERE tenant_id = ? AND id = ?').get(tid, link_id);
  if (!link) return res.status(404).json({ error: 'Payment link not found' });

  try {
    const valid = verifyRazorpaySignature({ orderId: link.gateway_order_id, paymentId: razorpay_payment_id, signature: razorpay_signature });
    if (!valid) {
      db.prepare("UPDATE payment_links SET status = 'failed' WHERE id = ?").run(link.id);
      return res.status(400).json({ error: 'Signature verification failed — payment not confirmed' });
    }
    markPaid(tid, link);
    res.json({ verified: true });
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// GET /payments/khalti/verify/:linkId
router.get('/khalti/verify/:linkId', async (req, res) => {
  const tid = tenantId(req);
  const link = db.prepare('SELECT * FROM payment_links WHERE tenant_id = ? AND id = ?').get(tid, req.params.linkId);
  if (!link) return res.status(404).json({ error: 'Payment link not found' });

  try {
    const result = await verifyKhaltiPayment(link.gateway_order_id);
    if (result.status === 'Completed') {
      markPaid(tid, link);
      return res.json({ verified: true, status: result.status });
    }
    db.prepare('UPDATE payment_links SET status = ? WHERE id = ?').run(result.status === 'Expired' ? 'expired' : 'created', link.id);
    res.json({ verified: false, status: result.status });
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// GET /payments/status/:linkId
router.get('/status/:linkId', (req, res) => {
  const tid = tenantId(req);
  const link = db.prepare('SELECT * FROM payment_links WHERE tenant_id = ? AND id = ?').get(tid, req.params.linkId);
  if (!link) return res.status(404).json({ error: 'Payment link not found' });
  res.json(link);
});

module.exports = router;
