'use strict';
const express = require('express');
const prisma = require('../lib/prisma');
const { validate, z, uuid } = require('../lib/validate');
const { asyncHandler } = require('../lib/errors');
const { requireStaff } = require('../middleware/auth');
const orders = require('../services/orders');
const S = require('../serializers');

/**
 * Staff operations. In a real product these would be called by the cafe's
 * tablet app and the rider app; here they let you drive an order by hand
 * (curl / Postman) when DEMO_ORDER_PROGRESSION is off.
 */
const router = express.Router();
router.use(requireStaff);

router.patch(
  '/orders/:id/status',
  validate({
    params: z.object({ id: uuid }),
    body: z.object({ status: z.enum(['CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED']), note: z.string().max(200).optional() }),
  }),
  asyncHandler(async (req, res) => {
    const order = await orders.transition(req.params.id, req.body.status, { note: req.body.note });
    res.json({ order: S.orderDetail(order) });
  }),
);

router.get('/orders', asyncHandler(async (_req, res) => {
  const list = await prisma.order.findMany({
    where: { status: { in: ['PLACED', 'CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP', 'OUT_FOR_DELIVERY'] } },
    include: { cafe: true, items: true },
    orderBy: { createdAt: 'asc' },
    take: 100,
  });
  res.json({ orders: list.map(S.orderSummary) });
}));

module.exports = router;
