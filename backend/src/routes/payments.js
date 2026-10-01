'use strict';
const express = require('express');
const config = require('../config/env');
const prisma = require('../lib/prisma');
const { validate, z, uuid } = require('../lib/validate');
const { asyncHandler, notFound, badRequest, AppError, unprocessable } = require('../lib/errors');
const { requireAuth } = require('../middleware/auth');
const { verifySignature, verifyWebhook } = require('../domain/paymentSignature');
const orders = require('../services/orders');
const S = require('../serializers');

const router = express.Router();

/** Which payment methods the app should offer (depends on server configuration). */
router.get('/methods', (_req, res) => {
  res.json({
    methods: [
      ...(config.payments.razorpayEnabled ? [{ id: 'RAZORPAY', title: 'UPI / Card / Netbanking', subtitle: 'Razorpay (test mode)', isMock: false }] : []),
      ...(config.payments.mockEnabled ? [{ id: 'MOCK', title: 'Demo payment', subtitle: 'Simulated — no real money moves', isMock: true }] : []),
      { id: 'CASH_ON_DELIVERY', title: 'Cash on delivery', subtitle: 'Pay when your order arrives', isMock: false },
    ],
  });
});

async function paymentForUser(paymentId, userId) {
  const payment = await prisma.payment.findFirst({ where: { id: paymentId, order: { userId } }, include: { order: true } });
  if (!payment) throw notFound('Payment');
  return payment;
}

/** Marks a payment successful and moves its order to PLACED — exactly once. */
async function markSucceeded(payment, providerPaymentId) {
  const updated = await prisma.payment.updateMany({
    where: { id: payment.id, status: { in: ['CREATED', 'PENDING', 'FAILED'] } },
    data: { status: 'SUCCEEDED', providerPaymentId, failureReason: null },
  });
  if (updated.count === 1) {
    const order = await prisma.order.findUnique({ where: { id: payment.orderId } });
    if (order.status === 'PENDING_PAYMENT') await orders.transition(order.id, 'PLACED', { note: 'Payment received' });
    else if (order.status === 'CANCELLED') {
      // Paid after the order was cancelled (e.g. slow UPI) → refund immediately.
      const fresh = await prisma.payment.findUnique({ where: { id: payment.id } });
      await prisma.payment.update({ where: { id: fresh.id }, data: { status: 'REFUNDED', failureReason: 'Order was cancelled before payment completed' } });
    }
  }
}

/** Start a new payment attempt for an unpaid order (after a failure/cancel). */
router.post(
  '/orders/:orderId/attempts',
  requireAuth,
  validate({ params: z.object({ orderId: uuid }), body: z.object({ method: z.enum(['RAZORPAY', 'MOCK']) }) }),
  asyncHandler(async (req, res) => {
    const order = await orders.loadOrderForUser(req.params.orderId, req.user.id);
    if (order.status !== 'PENDING_PAYMENT') throw new AppError(409, 'ALREADY_PAID', 'This order does not need payment');
    await prisma.payment.updateMany({ where: { orderId: order.id, status: { in: ['CREATED', 'PENDING'] } }, data: { status: 'CANCELLED' } });
    const payment = await orders.createPaymentAttempt(order, req.body.method);
    res.status(201).json({ payment: orders.checkoutPayload(payment) });
  }),
);

/** Called by the app after Razorpay checkout succeeds. The signature is the proof. */
router.post(
  '/:paymentId/verify',
  requireAuth,
  validate({
    params: z.object({ paymentId: uuid }),
    body: z.object({ razorpayOrderId: z.string().min(5), razorpayPaymentId: z.string().min(5), razorpaySignature: z.string().min(10) }),
  }),
  asyncHandler(async (req, res) => {
    const payment = await paymentForUser(req.params.paymentId, req.user.id);
    if (payment.provider !== 'RAZORPAY') throw badRequest('Not a Razorpay payment');
    if (payment.providerOrderId !== req.body.razorpayOrderId) throw badRequest('Payment does not belong to this order');
    const ok = verifySignature({
      orderId: payment.providerOrderId,
      paymentId: req.body.razorpayPaymentId,
      signature: req.body.razorpaySignature,
      secret: config.razorpay.keySecret,
    });
    if (!ok) {
      await prisma.payment.update({ where: { id: payment.id }, data: { status: 'FAILED', failureReason: 'Signature verification failed' } });
      throw unprocessable('We could not verify this payment', 'PAYMENT_VERIFICATION_FAILED');
    }
    await markSucceeded(payment, req.body.razorpayPaymentId);
    const order = await orders.loadOrderForUser(payment.orderId, req.user.id);
    res.json({ order: S.orderDetail(order) });
  }),
);

/** App reports a failed / cancelled checkout so the UI can offer a retry. */
router.post(
  '/:paymentId/failure',
  requireAuth,
  validate({ params: z.object({ paymentId: uuid }), body: z.object({ cancelled: z.boolean().default(false), reason: z.string().max(200).optional() }) }),
  asyncHandler(async (req, res) => {
    const payment = await paymentForUser(req.params.paymentId, req.user.id);
    await prisma.payment.updateMany({
      where: { id: payment.id, status: { in: ['CREATED', 'PENDING'] } },
      data: { status: req.body.cancelled ? 'CANCELLED' : 'FAILED', failureReason: req.body.reason || (req.body.cancelled ? 'Cancelled by user' : 'Payment failed') },
    });
    const order = await orders.loadOrderForUser(payment.orderId, req.user.id);
    res.json({ order: S.orderDetail(order) });
  }),
);

/**
 * MOCK provider — clearly labelled demo payments for local development and
 * interview demos without Razorpay keys. outcome: success | failure | cancel.
 */
router.post(
  '/:paymentId/mock-complete',
  requireAuth,
  validate({ params: z.object({ paymentId: uuid }), body: z.object({ outcome: z.enum(['success', 'failure', 'cancel']) }) }),
  asyncHandler(async (req, res) => {
    if (!config.payments.mockEnabled) throw unprocessable('Mock payments are disabled', 'PAYMENT_UNAVAILABLE');
    const payment = await paymentForUser(req.params.paymentId, req.user.id);
    if (payment.provider !== 'MOCK') throw badRequest('Not a mock payment');
    if (req.body.outcome === 'success') {
      await markSucceeded(payment, `mock_pay_${payment.id.slice(0, 8)}`);
    } else {
      await prisma.payment.updateMany({
        where: { id: payment.id, status: { in: ['CREATED', 'PENDING'] } },
        data: { status: req.body.outcome === 'cancel' ? 'CANCELLED' : 'FAILED', failureReason: req.body.outcome === 'cancel' ? 'Cancelled by user' : 'Demo payment declined' },
      });
    }
    const order = await orders.loadOrderForUser(payment.orderId, req.user.id);
    res.json({ order: S.orderDetail(order) });
  }),
);

/**
 * Razorpay webhook (payment.captured / payment.failed). A safety net for when
 * the app is killed before it can call /verify. Mounted with a raw body parser
 * in app.js because the signature covers the exact bytes.
 */
async function webhook(req, res) {
  const raw = req.body instanceof Buffer ? req.body.toString('utf8') : '';
  if (!verifyWebhook(raw, req.headers['x-razorpay-signature'], config.razorpay.webhookSecret)) {
    return res.status(400).json({ error: { code: 'BAD_SIGNATURE', message: 'Invalid webhook signature' } });
  }
  const event = JSON.parse(raw);
  const entity = event?.payload?.payment?.entity;
  if (entity?.order_id) {
    const payment = await prisma.payment.findUnique({ where: { providerOrderId: entity.order_id } });
    if (payment) {
      if (event.event === 'payment.captured') await markSucceeded(payment, entity.id);
      if (event.event === 'payment.failed') {
        await prisma.payment.updateMany({ where: { id: payment.id, status: { in: ['CREATED', 'PENDING'] } }, data: { status: 'FAILED', failureReason: entity.error_description || 'Payment failed' } });
      }
    }
  }
  res.json({ ok: true });
}

module.exports = { router, webhook: asyncHandler(webhook) };
