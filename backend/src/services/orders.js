'use strict';
const crypto = require('node:crypto');
const config = require('../config/env');
const prisma = require('../lib/prisma');
const { AppError, unprocessable, notFound, badRequest } = require('../lib/errors');
const P = require('../domain/pricing');
const OS = require('../domain/orderStatus');
const S = require('../serializers');
const { priceCart, publicCart } = require('./cartPricing');
const realtime = require('../realtime/socket');
const { notifyUser } = require('./notifications');
const razorpay = require('./razorpay');

const orderInclude = {
  cafe: true,
  items: true,
  payments: { orderBy: { createdAt: 'asc' } },
  events: true,
  coupon: true,
  review: true,
};

/** QB- + 6 chars from an alphabet without look-alikes (0/O, 1/I). */
function newOrderNumber() {
  const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  const bytes = crypto.randomBytes(6);
  return 'QB-' + [...bytes].map((b) => alphabet[b % alphabet.length]).join('');
}

async function loadOrderForUser(orderId, userId) {
  const order = await prisma.order.findFirst({ where: { id: orderId, userId }, include: orderInclude });
  if (!order) throw notFound('Order');
  return order;
}

/** Payment details the iOS app needs to open the Razorpay checkout or mock sheet. */
function checkoutPayload(payment) {
  if (!payment) return null;
  return {
    ...S.payment(payment),
    razorpayKeyId: payment.provider === 'RAZORPAY' ? config.razorpay.keyId : undefined,
    isMock: payment.provider === 'MOCK',
  };
}

async function createPaymentAttempt(order, provider) {
  if (provider === 'RAZORPAY') {
    if (!config.payments.razorpayEnabled) throw unprocessable('Online payment is not configured on the server', 'PAYMENT_UNAVAILABLE');
    const rp = await razorpay.createOrder({ amountPaise: order.totalPaise, receipt: order.orderNumber, notes: { orderId: order.id } });
    return prisma.payment.create({ data: { orderId: order.id, provider, amountPaise: order.totalPaise, providerOrderId: rp.id, status: 'CREATED' } });
  }
  if (provider === 'MOCK') {
    if (!config.payments.mockEnabled) throw unprocessable('Mock payments are disabled', 'PAYMENT_UNAVAILABLE');
    return prisma.payment.create({ data: { orderId: order.id, provider, amountPaise: order.totalPaise, providerOrderId: `mock_order_${crypto.randomBytes(8).toString('hex')}`, status: 'CREATED' } });
  }
  return prisma.payment.create({ data: { orderId: order.id, provider: 'CASH_ON_DELIVERY', amountPaise: order.totalPaise, status: 'PENDING' } });
}

/**
 * Creates an order from the user's server cart.
 *  - Re-prices everything from the database (client totals are ignored).
 *  - Idempotent per (user, idempotencyKey): a double tap or a network retry
 *    returns the same order instead of creating two.
 *  - Online payments → PENDING_PAYMENT until verified. Cash → PLACED immediately.
 */
async function createOrder(user, { addressId, paymentMethod, idempotencyKey }) {
  const existing = await prisma.order.findUnique({ where: { userId_idempotencyKey: { userId: user.id, idempotencyKey } }, include: orderInclude });
  if (existing) {
    const lastPayment = existing.payments[existing.payments.length - 1];
    return { order: existing, payment: lastPayment, replayed: true };
  }

  const address = await prisma.address.findFirst({ where: { id: addressId, userId: user.id } });
  if (!address) throw notFound('Address');

  const cart = await prisma.cart.findUnique({ where: { userId: user.id }, include: { items: true } });
  const priced = await priceCart(user.id, { items: cart?.items || [], couponCode: cart?.couponCode });
  if (!priced.canCheckout) {
    throw new AppError(422, 'CART_INVALID', priced.issues[0]?.message || 'Your cart cannot be checked out', { cart: publicCart(priced) });
  }
  if (priced.coupon && !priced.coupon.isValid) {
    throw new AppError(422, 'COUPON_INVALID', priced.coupon.message, { cart: publicCart(priced) });
  }
  if (priced.bill.subtotalPaise < 1) throw badRequest('Order total is invalid');

  const cafe = await prisma.cafe.findUnique({ where: { id: priced.cafe.id } });
  const km = P.distanceKm(cafe.latitude, cafe.longitude, address.latitude, address.longitude);
  if (km > 15) throw unprocessable(`${cafe.name} does not deliver to this address`, 'OUT_OF_DELIVERY_AREA');

  const status = paymentMethod === 'CASH_ON_DELIVERY' ? 'PLACED' : 'PENDING_PAYMENT';
  const order = await prisma.$transaction(async (tx) => {
    const created = await tx.order.create({
      data: {
        orderNumber: newOrderNumber(),
        userId: user.id,
        cafeId: cafe.id,
        addressId: address.id,
        couponId: priced.coupon?.isValid ? priced.coupon.couponId : null,
        status,
        paymentMethod,
        ...priced.bill,
        deliveryAddress: S.address(address),
        estimatedMinutes: P.estimateMinutes(cafe, km),
        idempotencyKey,
        isDemoTracking: true,
        items: {
          create: priced.lines.map((l) => ({
            menuItemId: l.menuItem.id,
            name: l.menuItem.name,
            unitPricePaise: l.unitPricePaise,
            quantity: l.quantity,
            options: l.options,
            lineTotalPaise: l.lineTotalPaise,
          })),
        },
        events: { create: [{ status }] },
      },
    });
    // The cart has become an order.
    if (cart) {
      await tx.cartItem.deleteMany({ where: { cartId: cart.id } });
      await tx.cart.update({ where: { id: cart.id }, data: { cafeId: null, couponCode: null } });
    }
    return created;
  });

  const payment = await createPaymentAttempt(order, paymentMethod);
  if (status === 'PLACED') await onPlaced(order.id);
  return { order: await loadOrderForUser(order.id, user.id), payment, replayed: false };
}

/** Side effects when an order is confirmed paid / placed: stock, popularity, notify. */
async function onPlaced(orderId) {
  const order = await prisma.order.findUnique({ where: { id: orderId }, include: { items: true, cafe: true } });
  await prisma.$transaction(order.items.map((i) =>
    prisma.menuItem.update({ where: { id: i.menuItemId }, data: { popularity: { increment: i.quantity } } })));
  for (const i of order.items) {
    // Decrement stock only for stock-tracked items; never below zero.
    await prisma.menuItem.updateMany({ where: { id: i.menuItemId, stock: { gte: i.quantity } }, data: { stock: { decrement: i.quantity } } });
  }
  await announce(order, 'PLACED');
}

async function announce(order, status) {
  const payload = { orderId: order.id, status, statusLabel: OS.LABELS[status], at: new Date().toISOString(), estimatedMinutes: order.estimatedMinutes };
  realtime.emitToOrder(order.id, order.userId, 'order:status', payload);
  const copy = OS.NOTIFY[status];
  if (copy) {
    const cafeName = order.cafe?.name || 'The cafe';
    await notifyUser(order.userId, {
      title: copy.title,
      body: copy.body.replace('{cafe}', cafeName).replace('{number}', order.orderNumber),
      orderId: order.id,
    });
  }
}

/**
 * The only function that changes an order's status. Uses a conditional update
 * (WHERE status = from) so two concurrent changes can't both win.
 */
async function transition(orderId, to, { note } = {}) {
  const order = await prisma.order.findUnique({ where: { id: orderId }, include: { cafe: true, payments: true, items: true } });
  if (!order) throw notFound('Order');
  OS.assertTransition(order.status, to);

  const updated = await prisma.order.updateMany({
    where: { id: orderId, status: order.status },
    data: { status: to, ...(to === 'DELIVERED' ? { deliveredAt: new Date() } : {}), ...(to === 'CANCELLED' && note ? { cancelReason: note } : {}) },
  });
  if (updated.count === 0) throw new AppError(409, 'STATUS_CHANGED', 'The order was updated by someone else, please refresh');
  await prisma.orderStatusEvent.create({ data: { orderId, status: to, note } });

  if (to === 'PLACED') {
    await onPlaced(orderId);
  } else if (to === 'CANCELLED') {
    await onCancelled(order);
    await announce(order, to);
  } else {
    if (to === 'DELIVERED') {
      const cod = order.payments.find((p) => p.provider === 'CASH_ON_DELIVERY' && p.status === 'PENDING');
      if (cod) await prisma.payment.update({ where: { id: cod.id }, data: { status: 'SUCCEEDED' } });
    }
    await announce(order, to);
  }
  return prisma.order.findUnique({ where: { id: orderId }, include: orderInclude });
}

async function onCancelled(order) {
  // Restore stock if it was taken (order had been placed).
  if (order.status !== 'PENDING_PAYMENT') {
    for (const i of order.items) {
      await prisma.menuItem.updateMany({ where: { id: i.menuItemId, stock: { not: null } }, data: { stock: { increment: i.quantity } } });
    }
  }
  for (const p of order.payments) {
    if (p.status === 'SUCCEEDED') {
      if (p.provider === 'RAZORPAY' && p.providerPaymentId && config.payments.razorpayEnabled) {
        try {
          await razorpay.refund(p.providerPaymentId, p.amountPaise);
        } catch (e) {
          console.error('refund failed', e.message);
          await prisma.payment.update({ where: { id: p.id }, data: { failureReason: `Refund pending: ${e.message}` } });
          continue;
        }
      }
      await prisma.payment.update({ where: { id: p.id }, data: { status: 'REFUNDED' } });
    } else if (['CREATED', 'PENDING'].includes(p.status)) {
      await prisma.payment.update({ where: { id: p.id }, data: { status: 'CANCELLED' } });
    }
  }
}

async function cancelByCustomer(user, orderId, reason) {
  const order = await loadOrderForUser(orderId, user.id);
  if (!OS.CUSTOMER_CANCELLABLE.has(order.status)) {
    throw new AppError(409, 'NOT_CANCELLABLE', 'This order is already being prepared and can no longer be cancelled');
  }
  return transition(order.id, 'CANCELLED', { note: reason || 'Cancelled by customer' });
}

/**
 * Illustrative rider position for the demo map. It moves along the straight
 * line from the cafe to the customer while OUT_FOR_DELIVERY. ALWAYS flagged
 * `isSimulated: true` — it is not GPS data.
 */
function simulatedRiderLocation(order, outForDeliveryAt, now = Date.now()) {
  if (order.status !== 'OUT_FOR_DELIVERY' || !outForDeliveryAt) return null;
  const dest = order.deliveryAddress;
  if (!dest || dest.latitude == null) return null;
  const totalMs = config.demoStepSeconds * 1000;
  const t = Math.max(0, Math.min(1, (now - new Date(outForDeliveryAt).getTime()) / totalMs));
  return {
    latitude: order.cafe.latitude + (dest.latitude - order.cafe.latitude) * t,
    longitude: order.cafe.longitude + (dest.longitude - order.cafe.longitude) * t,
    progress: Math.round(t * 100) / 100,
    isSimulated: true,
    at: new Date(now).toISOString(),
  };
}

module.exports = { createOrder, transition, cancelByCustomer, loadOrderForUser, createPaymentAttempt, checkoutPayload, simulatedRiderLocation, orderInclude, newOrderNumber };
