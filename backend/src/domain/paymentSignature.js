'use strict';
const crypto = require('node:crypto');

/**
 * Razorpay signature verification (server-side only — the key secret never
 * leaves the backend).
 *
 * Razorpay signs `${razorpay_order_id}|${razorpay_payment_id}` with HMAC-SHA256
 * using the key secret. We recompute it and compare in constant time.
 */
function expectedSignature(orderId, paymentId, secret) {
  return crypto.createHmac('sha256', secret).update(`${orderId}|${paymentId}`).digest('hex');
}

function verifySignature({ orderId, paymentId, signature, secret }) {
  if (!orderId || !paymentId || !signature || !secret) return false;
  const expected = Buffer.from(expectedSignature(orderId, paymentId, secret), 'utf8');
  const given = Buffer.from(String(signature), 'utf8');
  return expected.length === given.length && crypto.timingSafeEqual(expected, given);
}

/** Webhook bodies are signed over the raw request body. */
function verifyWebhook(rawBody, signature, webhookSecret) {
  if (!signature || !webhookSecret) return false;
  const expected = Buffer.from(crypto.createHmac('sha256', webhookSecret).update(rawBody).digest('hex'));
  const given = Buffer.from(String(signature));
  return expected.length === given.length && crypto.timingSafeEqual(expected, given);
}

module.exports = { expectedSignature, verifySignature, verifyWebhook };
