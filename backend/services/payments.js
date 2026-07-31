// Payment Gateway integrations. Same honest pattern as WhatsApp/Email:
// real API calls against each provider's actual documented contract, but
// they only work once you have your own merchant account and credentials
// — nobody can generate those for you.
//
//   razorpay -> RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET   (dashboard.razorpay.com)
//   esewa    -> ESEWA_MERCHANT_CODE, ESEWA_SECRET_KEY  (esewa.com.np merchant portal)
//   khalti   -> KHALTI_LIVE_SECRET_KEY                 (khalti.com merchant portal)
//
// Razorpay serves India; eSewa and Khalti serve Nepal — a consultancy only
// needs to configure whichever matches where their students actually pay
// from.

const crypto = require('crypto');

async function createRazorpayOrder({ amountInRupees, receiptId }) {
  const keyId = process.env.RAZORPAY_KEY_ID;
  const keySecret = process.env.RAZORPAY_KEY_SECRET;
  if (!keyId || !keySecret) {
    throw new Error('Razorpay not configured. Set RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET in .env.');
  }

  const auth = Buffer.from(`${keyId}:${keySecret}`).toString('base64');
  const res = await fetch('https://api.razorpay.com/v1/orders', {
    method: 'POST',
    headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      amount: Math.round(amountInRupees * 100), // Razorpay takes paise
      currency: 'INR',
      receipt: receiptId,
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`Razorpay order creation failed: ${JSON.stringify(data)}`);

  return {
    gateway_order_id: data.id,
    // The actual checkout happens client-side with Razorpay's Checkout.js
    // using this order id + your public key_id — there's no plain
    // "payment_url" for Razorpay the way eSewa/Khalti provide one.
    checkout_config: { key: keyId, order_id: data.id, amount: data.amount, currency: data.currency },
  };
}

function verifyRazorpaySignature({ orderId, paymentId, signature }) {
  const keySecret = process.env.RAZORPAY_KEY_SECRET;
  if (!keySecret) throw new Error('Razorpay not configured.');
  const expected = crypto.createHmac('sha256', keySecret).update(`${orderId}|${paymentId}`).digest('hex');
  return expected === signature;
}

function buildEsewaPaymentForm({ amountInRupees, transactionId, successUrl, failureUrl }) {
  const merchantCode = process.env.ESEWA_MERCHANT_CODE;
  const secretKey = process.env.ESEWA_SECRET_KEY;
  if (!merchantCode || !secretKey) {
    throw new Error('eSewa not configured. Set ESEWA_MERCHANT_CODE and ESEWA_SECRET_KEY in .env.');
  }

  // eSewa's v2 API is a signed form POST, not a redirect URL you can just
  // link to — the signature covers these exact fields in this exact order.
  const fields = {
    amount: amountInRupees.toString(),
    tax_amount: '0',
    total_amount: amountInRupees.toString(),
    transaction_uuid: transactionId,
    product_code: merchantCode,
    product_service_charge: '0',
    product_delivery_charge: '0',
    success_url: successUrl,
    failure_url: failureUrl,
    signed_field_names: 'total_amount,transaction_uuid,product_code',
  };
  const signatureBase = `total_amount=${fields.total_amount},transaction_uuid=${fields.transaction_uuid},product_code=${fields.product_code}`;
  fields.signature = crypto.createHmac('sha256', secretKey).update(signatureBase).digest('base64');

  return { action_url: 'https://rc-epay.esewa.com.np/api/epay/main/v2/form', fields };
}

async function initiateKhaltiPayment({ amountInRupees, purchaseOrderId, purchaseOrderName, returnUrl, customerPhone }) {
  const secretKey = process.env.KHALTI_LIVE_SECRET_KEY;
  if (!secretKey) throw new Error('Khalti not configured. Set KHALTI_LIVE_SECRET_KEY in .env.');

  const res = await fetch('https://khalti.com/api/v2/epayment/initiate/', {
    method: 'POST',
    headers: { Authorization: `Key ${secretKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      return_url: returnUrl,
      website_url: returnUrl,
      amount: Math.round(amountInRupees * 100), // Khalti takes paisa
      purchase_order_id: purchaseOrderId,
      purchase_order_name: purchaseOrderName,
      customer_info: customerPhone ? { phone: customerPhone } : undefined,
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`Khalti payment initiation failed: ${JSON.stringify(data)}`);

  return { gateway_order_id: data.pidx, payment_url: data.payment_url };
}

async function verifyKhaltiPayment(pidx) {
  const secretKey = process.env.KHALTI_LIVE_SECRET_KEY;
  if (!secretKey) throw new Error('Khalti not configured.');

  const res = await fetch('https://khalti.com/api/v2/epayment/lookup/', {
    method: 'POST',
    headers: { Authorization: `Key ${secretKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ pidx }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`Khalti lookup failed: ${JSON.stringify(data)}`);
  return data; // { status: 'Completed' | 'Pending' | 'Expired' | ... }
}

module.exports = {
  createRazorpayOrder,
  verifyRazorpaySignature,
  buildEsewaPaymentForm,
  initiateKhaltiPayment,
  verifyKhaltiPayment,
};
