'use strict';
const express = require('express');
const prisma = require('../lib/prisma');
const { validate, z, uuid } = require('../lib/validate');
const { asyncHandler, notFound, conflict } = require('../lib/errors');
const { requireAuth } = require('../middleware/auth');
const { lineKey } = require('../domain/pricing');
const { priceCart, publicCart, MAX_QTY_PER_LINE } = require('../services/cartPricing');

/**
 * Server-side cart. The iOS app keeps its own Core Data copy so the cart works
 * offline and for guests; when signed in it syncs with PUT /cart (replace) and
 * then uses the granular endpoints.
 */
const router = express.Router();
router.use(requireAuth);

const lineInput = z.object({
  menuItemId: uuid,
  quantity: z.number().int().min(1).max(MAX_QTY_PER_LINE),
  optionIds: z.array(uuid).max(20).default([]),
});

async function getOrCreateCart(userId) {
  return prisma.cart.upsert({ where: { userId }, create: { userId }, update: {}, include: { items: { orderBy: { createdAt: 'asc' } } } });
}

async function respond(res, userId, status = 200) {
  const cart = await getOrCreateCart(userId);
  const priced = await priceCart(userId, { items: cart.items, couponCode: cart.couponCode });
  res.status(status).json({ cart: publicCart(priced) });
}

router.get('/', asyncHandler(async (req, res) => respond(res, req.user.id)));

/** Replace the whole cart (used when syncing the local cart after sign-in). */
router.put(
  '/',
  validate({ body: z.object({ items: z.array(lineInput).max(50), couponCode: z.string().trim().max(30).nullable().optional() }) }),
  asyncHandler(async (req, res) => {
    const cart = await getOrCreateCart(req.user.id);
    // Merge duplicate lines from the client.
    const merged = new Map();
    for (const l of req.body.items) {
      const key = lineKey(l.menuItemId, l.optionIds);
      const prev = merged.get(key);
      merged.set(key, { ...l, quantity: Math.min(MAX_QTY_PER_LINE, (prev?.quantity || 0) + l.quantity), lineKey: key });
    }
    const cafeIds = await distinctCafeIds([...merged.values()].map((l) => l.menuItemId));
    if (cafeIds.length > 1) throw conflict('You can only order from one cafe at a time', 'MULTIPLE_CAFES');
    await prisma.$transaction([
      prisma.cartItem.deleteMany({ where: { cartId: cart.id } }),
      prisma.cartItem.createMany({ data: [...merged.values()].map((l) => ({ cartId: cart.id, menuItemId: l.menuItemId, quantity: l.quantity, optionIds: l.optionIds, lineKey: l.lineKey })) }),
      prisma.cart.update({ where: { id: cart.id }, data: { cafeId: cafeIds[0] || null, couponCode: req.body.couponCode ?? null } }),
    ]);
    await respond(res, req.user.id);
  }),
);

async function distinctCafeIds(menuItemIds) {
  if (!menuItemIds.length) return [];
  const rows = await prisma.menuItem.findMany({ where: { id: { in: menuItemIds } }, select: { cafeId: true } });
  return [...new Set(rows.map((r) => r.cafeId))];
}

/**
 * Add an item. If the cart holds another cafe's items the request fails with
 * 409 CART_CAFE_CONFLICT unless `replaceCart: true` (the app asks the user first).
 */
router.post(
  '/items',
  validate({ body: lineInput.extend({ replaceCart: z.boolean().default(false) }) }),
  asyncHandler(async (req, res) => {
    const { menuItemId, quantity, optionIds, replaceCart } = req.body;
    const item = await prisma.menuItem.findUnique({ where: { id: menuItemId } });
    if (!item) throw notFound('Menu item');
    const cart = await getOrCreateCart(req.user.id);

    if (cart.cafeId && cart.cafeId !== item.cafeId && cart.items.length > 0) {
      if (!replaceCart) throw conflict('Your cart has items from another cafe. Start a new cart?', 'CART_CAFE_CONFLICT');
      await prisma.cartItem.deleteMany({ where: { cartId: cart.id } });
      await prisma.cart.update({ where: { id: cart.id }, data: { couponCode: null } });
    }
    const key = lineKey(menuItemId, optionIds);
    const existing = await prisma.cartItem.findUnique({ where: { cartId_lineKey: { cartId: cart.id, lineKey: key } } });
    if (existing) {
      await prisma.cartItem.update({ where: { id: existing.id }, data: { quantity: Math.min(MAX_QTY_PER_LINE, existing.quantity + quantity) } });
    } else {
      await prisma.cartItem.create({ data: { cartId: cart.id, menuItemId, quantity, optionIds, lineKey: key } });
    }
    await prisma.cart.update({ where: { id: cart.id }, data: { cafeId: item.cafeId } });
    await respond(res, req.user.id, 201);
  }),
);

/** Change quantity and/or customization of a line. quantity 0 removes it. */
router.patch(
  '/items/:lineId',
  validate({
    params: z.object({ lineId: uuid }),
    body: z.object({ quantity: z.number().int().min(0).max(MAX_QTY_PER_LINE).optional(), optionIds: z.array(uuid).max(20).optional() }),
  }),
  asyncHandler(async (req, res) => {
    const cart = await getOrCreateCart(req.user.id);
    const line = cart.items.find((i) => i.id === req.params.lineId);
    if (!line) throw notFound('Cart item');
    if (req.body.quantity === 0) {
      await prisma.cartItem.delete({ where: { id: line.id } });
    } else {
      const optionIds = req.body.optionIds ?? line.optionIds;
      const key = lineKey(line.menuItemId, optionIds);
      const clash = cart.items.find((i) => i.lineKey === key && i.id !== line.id);
      if (clash) {
        // Editing options made it identical to another line → merge them.
        await prisma.$transaction([
          prisma.cartItem.update({ where: { id: clash.id }, data: { quantity: Math.min(MAX_QTY_PER_LINE, clash.quantity + (req.body.quantity ?? line.quantity)) } }),
          prisma.cartItem.delete({ where: { id: line.id } }),
        ]);
      } else {
        await prisma.cartItem.update({ where: { id: line.id }, data: { quantity: req.body.quantity ?? line.quantity, optionIds, lineKey: key } });
      }
    }
    await respond(res, req.user.id);
  }),
);

router.delete('/items/:lineId', validate({ params: z.object({ lineId: uuid }) }), asyncHandler(async (req, res) => {
  const cart = await getOrCreateCart(req.user.id);
  const deleted = await prisma.cartItem.deleteMany({ where: { id: req.params.lineId, cartId: cart.id } });
  if (deleted.count === 0) throw notFound('Cart item');
  await respond(res, req.user.id);
}));

router.delete('/', asyncHandler(async (req, res) => {
  const cart = await getOrCreateCart(req.user.id);
  await prisma.$transaction([
    prisma.cartItem.deleteMany({ where: { cartId: cart.id } }),
    prisma.cart.update({ where: { id: cart.id }, data: { cafeId: null, couponCode: null } }),
  ]);
  await respond(res, req.user.id);
}));

router.put('/coupon', validate({ body: z.object({ code: z.string().trim().min(2).max(30).nullable() }) }), asyncHandler(async (req, res) => {
  const cart = await getOrCreateCart(req.user.id);
  await prisma.cart.update({ where: { id: cart.id }, data: { couponCode: req.body.code ? req.body.code.toUpperCase() : null } });
  await respond(res, req.user.id);
}));

/** Checkout gate: re-prices from the database and lists every blocking issue. */
router.post('/validate', asyncHandler(async (req, res) => {
  const cart = await getOrCreateCart(req.user.id);
  const priced = await priceCart(req.user.id, { items: cart.items, couponCode: cart.couponCode });
  res.json({ cart: publicCart(priced) });
}));

module.exports = router;
