'use strict';
const express = require('express');
const prisma = require('../lib/prisma');
const { validate, z, uuid, pagination, paginate, pageMeta } = require('../lib/validate');
const { asyncHandler, notFound, AppError } = require('../lib/errors');
const { requireAuth } = require('../middleware/auth');
const S = require('../serializers');

const router = express.Router();

/** Reviews are only allowed for the user's own DELIVERED orders, once each. */
router.post(
  '/orders/:orderId/review',
  requireAuth,
  validate({
    params: z.object({ orderId: uuid }),
    body: z.object({ rating: z.number().int().min(1, 'Pick 1 to 5 stars').max(5), comment: z.string().trim().max(500).optional() }),
  }),
  asyncHandler(async (req, res) => {
    const order = await prisma.order.findFirst({ where: { id: req.params.orderId, userId: req.user.id }, include: { review: true } });
    if (!order) throw notFound('Order');
    if (order.status !== 'DELIVERED') throw new AppError(422, 'ORDER_NOT_DELIVERED', 'You can rate an order once it has been delivered');
    if (order.review) throw new AppError(409, 'ALREADY_REVIEWED', 'You have already rated this order');

    const review = await prisma.$transaction(async (tx) => {
      const r = await tx.review.create({
        data: { orderId: order.id, userId: req.user.id, cafeId: order.cafeId, rating: req.body.rating, comment: req.body.comment || null },
        include: { user: true, cafe: true },
      });
      // Keep the cafe's running average in sync (incremental mean).
      const cafe = await tx.cafe.findUnique({ where: { id: order.cafeId } });
      const count = cafe.ratingCount + 1;
      await tx.cafe.update({ where: { id: cafe.id }, data: { ratingCount: count, rating: (cafe.rating * cafe.ratingCount + req.body.rating) / count } });
      return r;
    });
    res.status(201).json({ review: S.review(review) });
  }),
);

router.get(
  '/cafes/:cafeId/reviews',
  validate({ params: z.object({ cafeId: uuid }), query: pagination }),
  asyncHandler(async (req, res) => {
    const where = { cafeId: req.params.cafeId };
    const [list, total, agg] = await Promise.all([
      prisma.review.findMany({ where, include: { user: true }, orderBy: { createdAt: 'desc' }, ...paginate(req.query) }),
      prisma.review.count({ where }),
      prisma.review.groupBy({ by: ['rating'], where, _count: { rating: true } }),
    ]);
    const distribution = Object.fromEntries([1, 2, 3, 4, 5].map((n) => [n, agg.find((a) => a.rating === n)?._count.rating || 0]));
    res.json({ reviews: list.map(S.review), distribution, meta: pageMeta(req.query, total) });
  }),
);

router.get('/me/reviews', requireAuth, validate({ query: pagination }), asyncHandler(async (req, res) => {
  const where = { userId: req.user.id };
  const [list, total] = await Promise.all([
    prisma.review.findMany({ where, include: { cafe: true }, orderBy: { createdAt: 'desc' }, ...paginate(req.query) }),
    prisma.review.count({ where }),
  ]);
  res.json({ reviews: list.map(S.review), meta: pageMeta(req.query, total) });
}));

module.exports = router;
