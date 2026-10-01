'use strict';
const express = require('express');
const prisma = require('../lib/prisma');
const { validate, z, uuid, pagination, paginate, pageMeta } = require('../lib/validate');
const { asyncHandler } = require('../lib/errors');
const { requireAuth } = require('../middleware/auth');
const S = require('../serializers');
const orders = require('../services/orders');

const router = express.Router();
router.use(requireAuth);

const ACTIVE = ['PLACED', 'CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP', 'OUT_FOR_DELIVERY'];

/**
 * POST /orders — place an order from the server cart.
 * Header or body `idempotencyKey` (a UUID the app generates once per checkout
 * attempt) makes double taps and retries safe.
 */
router.post(
  '/',
  validate({
    body: z.object({
      addressId: uuid,
      paymentMethod: z.enum(['RAZORPAY', 'MOCK', 'CASH_ON_DELIVERY']),
      idempotencyKey: z.string().min(8).max(64),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { order, payment, replayed } = await orders.createOrder(req.user, req.body);
    res.status(replayed ? 200 : 201).json({ order: S.orderDetail(order), payment: orders.checkoutPayload(payment), replayed });
  }),
);

router.get('/active', asyncHandler(async (req, res) => {
  const list = await prisma.order.findMany({
    where: { userId: req.user.id, status: { in: ACTIVE } },
    include: { cafe: true, items: true, review: true },
    orderBy: { createdAt: 'desc' },
  });
  res.json({ orders: list.map(S.orderSummary) });
}));

router.get(
  '/',
  validate({ query: pagination.extend({ status: z.enum(['active', 'past', 'all']).default('all') }) }),
  asyncHandler(async (req, res) => {
    const statusFilter = {
      active: { in: ACTIVE },
      past: { in: ['DELIVERED', 'CANCELLED'] },
      all: { not: 'PENDING_PAYMENT' },
    }[req.query.status];
    const where = { userId: req.user.id, status: statusFilter };
    const [list, total] = await Promise.all([
      prisma.order.findMany({ where, include: { cafe: true, items: true, review: true }, orderBy: { createdAt: 'desc' }, ...paginate(req.query) }),
      prisma.order.count({ where }),
    ]);
    res.json({ orders: list.map(S.orderSummary), meta: pageMeta(req.query, total) });
  }),
);

router.get('/:id', validate({ params: z.object({ id: uuid }) }), asyncHandler(async (req, res) => {
  const order = await orders.loadOrderForUser(req.params.id, req.user.id);
  res.json({ order: S.orderDetail(order) });
}));

/** Tracking snapshot: status timeline + (demo) rider position + cafe/destination coordinates. */
router.get('/:id/tracking', validate({ params: z.object({ id: uuid }) }), asyncHandler(async (req, res) => {
  const order = await orders.loadOrderForUser(req.params.id, req.user.id);
  const outEvent = order.events.find((e) => e.status === 'OUT_FOR_DELIVERY');
  res.json({
    orderId: order.id,
    status: order.status,
    estimatedMinutes: order.estimatedMinutes,
    placedAt: order.createdAt,
    cafeLocation: { latitude: order.cafe.latitude, longitude: order.cafe.longitude },
    destination: order.deliveryAddress?.latitude != null ? { latitude: order.deliveryAddress.latitude, longitude: order.deliveryAddress.longitude } : null,
    rider: orders.simulatedRiderLocation(order, outEvent?.createdAt),
    isDemoTracking: order.isDemoTracking,
    timeline: S.orderDetail(order).timeline,
  });
}));

router.post(
  '/:id/cancel',
  validate({ params: z.object({ id: uuid }), body: z.object({ reason: z.string().trim().max(200).optional() }) }),
  asyncHandler(async (req, res) => {
    const order = await orders.cancelByCustomer(req.user, req.params.id, req.body.reason);
    res.json({ order: S.orderDetail(order) });
  }),
);

/**
 * Reorder: puts the still-available items of a past order back in the cart
 * (replacing it) and returns the re-priced cart plus anything that was skipped.
 */
router.post('/:id/reorder', validate({ params: z.object({ id: uuid }) }), asyncHandler(async (req, res) => {
  const past = await orders.loadOrderForUser(req.params.id, req.user.id);
  const { lineKey } = require('../domain/pricing');
  const { priceCart, publicCart } = require('../services/cartPricing');
  const menu = await prisma.menuItem.findMany({ where: { id: { in: past.items.map((i) => i.menuItemId) } } });
  const available = new Map(menu.filter((m) => m.isAvailable).map((m) => [m.id, m]));
  const skipped = past.items.filter((i) => !available.has(i.menuItemId)).map((i) => i.name);

  const cart = await prisma.cart.upsert({ where: { userId: req.user.id }, create: { userId: req.user.id }, update: {} });
  const merged = new Map();
  for (const i of past.items.filter((it) => available.has(it.menuItemId))) {
    const optionIds = (i.options || []).map((o) => o.id);
    const key = lineKey(i.menuItemId, optionIds);
    merged.set(key, { menuItemId: i.menuItemId, optionIds, quantity: (merged.get(key)?.quantity || 0) + i.quantity, lineKey: key });
  }
  await prisma.$transaction([
    prisma.cartItem.deleteMany({ where: { cartId: cart.id } }),
    prisma.cartItem.createMany({ data: [...merged.values()].map((l) => ({ ...l, cartId: cart.id })) }),
    prisma.cart.update({ where: { id: cart.id }, data: { cafeId: past.cafeId, couponCode: null } }),
  ]);
  const items = await prisma.cartItem.findMany({ where: { cartId: cart.id }, orderBy: { createdAt: 'asc' } });
  res.json({ cart: publicCart(await priceCart(req.user.id, { items })), skippedItems: skipped });
}));

module.exports = router;
