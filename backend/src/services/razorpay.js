'use strict';
const config = require('../config/env');
const { AppError } = require('../lib/errors');

/**
 * Minimal Razorpay REST client (Orders + Refunds APIs) using the built-in
 * fetch. Only used when RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET are set.
 * Test-mode keys (rzp_test_...) never move real money.
 */
const BASE = 'https://api.razorpay.com/v1';

function authHeader() {
  return 'Basic ' + Buffer.from(`${config.razorpay.keyId}:${config.razorpay.keySecret}`).toString('base64');
}

async function call(path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST',
    headers: { Authorization: authHeader(), 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new AppError(502, 'PAYMENT_PROVIDER_ERROR', json?.error?.description || `Razorpay request failed (${res.status})`);
  }
  return json;
}

/** Creates a Razorpay order. Amount is in paise. */
function createOrder({ amountPaise, receipt, notes }) {
  return call('/orders', { amount: amountPaise, currency: 'INR', receipt, notes });
}

function refund(paymentId, amountPaise) {
  return call(`/payments/${paymentId}/refund`, { amount: amountPaise, speed: 'normal' });
}

module.exports = { createOrder, refund };
