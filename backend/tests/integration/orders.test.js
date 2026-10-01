'use strict';
const { test, describe, before, after } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { io } = require('socket.io-client');
const { startServer, newUser, addAddress, openCafeItem, prisma } = require('./helpers');
const { expectedSignature } = require('../../src/domain/paymentSignature');
const demo = require('../../src/services/demoProgression');

let s;
before(async () => { s = await startServer(); });
after(async () => { await s.stop(); await prisma.$disconnect(); });

async function cartWith(token, quantity = 2) {
  const { item } = await openCafeItem();
  const r = await s.api('POST', '/api/v1/cart/items', { token, body: { menuItemId: item.id, quantity } });
  assert.equal(r.status, 201, JSON.stringify(r.body));
  return { item, cart: r.body.cart };
}

describe('cart API', () => {
  test('adding the same item twice merges into one line', async () => {
    const { token } = await newUser(s.api);
    const { item } = await cartWith(token, 1);
    const r = await s.api('POST', '/api/v1/cart/items', { token, body: { menuItemId: item.id, quantity: 2 } });
    assert.equal(r.body.cart.lines.length, 1);
    assert.equal(r.body.cart.lines[0].quantity, 3);
    assert.equal(r.body.cart.bill.subtotalPaise, item.pricePaise * 3);
  });

  test('customizations are priced on the server and validated', async () => {
    const { token } = await newUser(s.api);
    const { item } = await openCafeItem({ withCustomizations: true });
    const size = item.customizations[0];
    const missing = await s.api('POST', '/api/v1/cart/items', { token, body: { menuItemId: item.id, quantity: 1, optionIds: [] } });
    assert.equal(missing.status, 201);
    assert.equal(missing.body.cart.lines[0].issue.code, 'INVALID_OPTIONS');
    assert.equal(missing.body.cart.canCheckout, false);

    const full = size.options.find((o) => o.extraPricePaise > 0);
    await s.api('DELETE', '/api/v1/cart', { token });
    const ok = await s.api('POST', '/api/v1/cart/items', { token, body: { menuItemId: item.id, quantity: 2, optionIds: [full.id] } });
    assert.equal(ok.body.cart.lines[0].unitPricePaise, item.pricePaise + full.extraPricePaise);
    assert.equal(ok.body.cart.canCheckout, true);
  });

  test('items from another cafe need explicit replacement', async () => {
    const { token } = await newUser(s.api);
    await cartWith(token);
    const other = await prisma.menuItem.findFirst({ where: { cafe: { slug: 'ember-roastery' }, customizations: { none: {} } } });
    const conflict = await s.api('POST', '/api/v1/cart/items', { token, body: { menuItemId: other.id, quantity: 1 } });
    assert.equal(conflict.status, 409);
    assert.equal(conflict.body.error.code, 'CART_CAFE_CONFLICT');
    const replaced = await s.api('POST', '/api/v1/cart/items', { token, body: { menuItemId: other.id, quantity: 1, replaceCart: true } });
    assert.equal(replaced.status, 201);
    assert.equal(replaced.body.cart.lines.length, 1);
  });

  test('update quantity, then quantity 0 removes the line', async () => {
    const { token } = await newUser(s.api);
    const { cart } = await cartWith(token);
    const lineId = cart.lines[0].id;
    const upd = await s.api('PATCH', `/api/v1/cart/items/${lineId}`, { token, body: { quantity: 5 } });
    assert.equal(upd.body.cart.lines[0].quantity, 5);
    const del = await s.api('PATCH', `/api/v1/cart/items/${lineId}`, { token, body: { quantity: 0 } });
    assert.equal(del.body.cart.lines.length, 0);
  });

  test('coupon: below minimum, valid, then usage counted', async () => {
    const { token } = await newUser(s.api);
    await cartWith(token, 1); // ₹69 chai — below WELCOME50 minimum
    let r = await s.api('PUT', '/api/v1/cart/coupon', { token, body: { code: 'welcome50' } });
    assert.equal(r.body.cart.coupon.isValid, false);
    assert.match(r.body.cart.coupon.message, /more/);

    const { item } = await openCafeItem();
    await s.api('PUT', '/api/v1/cart', { token, body: { items: [{ menuItemId: item.id, quantity: 6 }], couponCode: 'WELCOME50' } });
    r = await s.api('GET', '/api/v1/cart', { token });
    assert.equal(r.body.cart.coupon.isValid, true);
    assert.equal(r.body.cart.bill.discountPaise, Math.min(10000, Math.floor((item.pricePaise * 6) / 2)));
  });

  test('expired coupon is rejected', async () => {
    const { token } = await newUser(s.api);
    await cartWith(token, 5);
    const r = await s.api('PUT', '/api/v1/cart/coupon', { token, body: { code: 'MONSOON20' } });
    assert.equal(r.body.cart.coupon.isValid, false);
    assert.match(r.body.cart.coupon.message, /expired/);
  });

  test('client-sent prices are ignored', async () => {
    const { token } = await newUser(s.api);
    const { item } = await openCafeItem();
    const r = await s.api('PUT', '/api/v1/cart', { token, body: { items: [{ menuItemId: item.id, quantity: 1, pricePaise: 1 }] } });
    assert.equal(r.body.cart.lines[0].unitPricePaise, item.pricePaise);
  });
});

describe('orders, payments and live tracking', () => {
  test('mock payment → PLACED → demo progression → DELIVERED with socket events, then review', async () => {
    const { token } = await newUser(s.api);
    const address = await addAddress(s.api, token);
    const { item } = await cartWith(token, 3);
    const idempotencyKey = crypto.randomUUID();

    const created = await s.api('POST', '/api/v1/orders', { token, body: { addressId: address.id, paymentMethod: 'MOCK', idempotencyKey } });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const order = created.body.order;
    assert.equal(order.status, 'PENDING_PAYMENT');
    assert.equal(order.bill.subtotalPaise, item.pricePaise * 3);
    assert.equal(created.body.payment.isMock, true);

    // Double tap / retry returns the same order.
    const again = await s.api('POST', '/api/v1/orders', { token, body: { addressId: address.id, paymentMethod: 'MOCK', idempotencyKey } });
    assert.equal(again.status, 200);
    assert.equal(again.body.order.id, order.id);
    assert.equal(await prisma.order.count({ where: { idempotencyKey } }), 1);

    // Cart was converted into the order.
    const cart = await s.api('GET', '/api/v1/cart', { token });
    assert.equal(cart.body.cart.lines.length, 0);

    // Subscribe to live updates.
    const socket = io(s.base, { auth: { token }, transports: ['websocket'] });
    const statuses = [];
    socket.on('order:status', (e) => statuses.push(e.status));
    const sub = await new Promise((resolve) => socket.on('connect', () => socket.emit('order:subscribe', order.id, resolve)));
    assert.equal(sub.ok, true);

    const paid = await s.api('POST', `/api/v1/payments/${created.body.payment.id}/mock-complete`, { token, body: { outcome: 'success' } });
    assert.equal(paid.status, 200);
    assert.equal(paid.body.order.status, 'PLACED');

    // Review not allowed before delivery.
    const early = await s.api('POST', `/api/v1/orders/${order.id}/review`, { token, body: { rating: 5 } });
    assert.equal(early.status, 422);

    // DEMO_STEP_SECONDS=0 so each tick advances one step.
    for (let i = 0; i < 5; i++) {
      await prisma.order.update({ where: { id: order.id }, data: { updatedAt: new Date(Date.now() - 1000) } });
      await demo.tick();
    }
    await new Promise((r) => setTimeout(r, 300));
    socket.close();

    assert.deepEqual(statuses, ['PLACED', 'CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP', 'OUT_FOR_DELIVERY', 'DELIVERED']);
    const detail = await s.api('GET', `/api/v1/orders/${order.id}`, { token });
    assert.equal(detail.body.order.status, 'DELIVERED');
    assert.equal(detail.body.order.timeline.length, 7);
    assert.equal(detail.body.order.canReview, true);

    const notifications = await s.api('GET', '/api/v1/notifications', { token });
    assert.ok(notifications.body.notifications.some((n) => n.title.startsWith('Delivered')));

    const review = await s.api('POST', `/api/v1/orders/${order.id}/review`, { token, body: { rating: 5, comment: 'Lovely chai!' } });
    assert.equal(review.status, 201);
    const twice = await s.api('POST', `/api/v1/orders/${order.id}/review`, { token, body: { rating: 4 } });
    assert.equal(twice.status, 409);

    const history = await s.api('GET', '/api/v1/orders?status=past', { token });
    assert.equal(history.body.orders[0].id, order.id);
    assert.equal(history.body.orders[0].isReviewed, true);
  });

  test('razorpay signature verification (test secret) places the order; bad signature fails', async () => {
    const { token } = await newUser(s.api);
    const address = await addAddress(s.api, token);
    await cartWith(token, 2);
    const created = await s.api('POST', '/api/v1/orders', { token, body: { addressId: address.id, paymentMethod: 'MOCK', idempotencyKey: crypto.randomUUID() } });
    // Simulate a Razorpay attempt row (creating a real Razorpay order needs live keys).
    const payment = await prisma.payment.create({ data: { orderId: created.body.order.id, provider: 'RAZORPAY', amountPaise: created.body.order.totalPaise, providerOrderId: `order_test_${Date.now()}` } });

    const bad = await s.api('POST', `/api/v1/payments/${payment.id}/verify`, {
      token, body: { razorpayOrderId: payment.providerOrderId, razorpayPaymentId: 'pay_fake123', razorpaySignature: 'deadbeef'.repeat(8) },
    });
    assert.equal(bad.status, 422);

    const signature = expectedSignature(payment.providerOrderId, 'pay_real123', process.env.RAZORPAY_KEY_SECRET);
    const good = await s.api('POST', `/api/v1/payments/${payment.id}/verify`, {
      token, body: { razorpayOrderId: payment.providerOrderId, razorpayPaymentId: 'pay_real123', razorpaySignature: signature },
    });
    assert.equal(good.status, 200, JSON.stringify(good.body));
    assert.equal(good.body.order.status, 'PLACED');
  });

  test('failed payment keeps order unpaid and allows a retry attempt', async () => {
    const { token } = await newUser(s.api);
    const address = await addAddress(s.api, token);
    await cartWith(token, 2);
    const created = await s.api('POST', '/api/v1/orders', { token, body: { addressId: address.id, paymentMethod: 'MOCK', idempotencyKey: crypto.randomUUID() } });
    const failed = await s.api('POST', `/api/v1/payments/${created.body.payment.id}/mock-complete`, { token, body: { outcome: 'failure' } });
    assert.equal(failed.body.order.status, 'PENDING_PAYMENT');
    assert.equal(failed.body.order.payments[0].status, 'FAILED');

    const retry = await s.api('POST', `/api/v1/payments/orders/${created.body.order.id}/attempts`, { token, body: { method: 'MOCK' } });
    assert.equal(retry.status, 201);
    const ok = await s.api('POST', `/api/v1/payments/${retry.body.payment.id}/mock-complete`, { token, body: { outcome: 'success' } });
    assert.equal(ok.body.order.status, 'PLACED');
  });

  test('cash order can be cancelled before preparing, not after; paid orders get refunded', async () => {
    const { token } = await newUser(s.api);
    const address = await addAddress(s.api, token);
    await cartWith(token, 2);
    const created = await s.api('POST', '/api/v1/orders', { token, body: { addressId: address.id, paymentMethod: 'CASH_ON_DELIVERY', idempotencyKey: crypto.randomUUID() } });
    assert.equal(created.body.order.status, 'PLACED');
    const cancelled = await s.api('POST', `/api/v1/orders/${created.body.order.id}/cancel`, { token, body: { reason: 'Changed my mind' } });
    assert.equal(cancelled.body.order.status, 'CANCELLED');
    assert.equal(cancelled.body.order.payments[0].status, 'CANCELLED');

    await cartWith(token, 2);
    const paidOrder = await s.api('POST', '/api/v1/orders', { token, body: { addressId: address.id, paymentMethod: 'MOCK', idempotencyKey: crypto.randomUUID() } });
    await s.api('POST', `/api/v1/payments/${paidOrder.body.payment.id}/mock-complete`, { token, body: { outcome: 'success' } });
    const refunded = await s.api('POST', `/api/v1/orders/${paidOrder.body.order.id}/cancel`, { token, body: {} });
    assert.equal(refunded.body.order.payments[0].status, 'REFUNDED');

    await cartWith(token, 2);
    const third = await s.api('POST', '/api/v1/orders', { token, body: { addressId: address.id, paymentMethod: 'CASH_ON_DELIVERY', idempotencyKey: crypto.randomUUID() } });
    const id = third.body.order.id;
    const admin = { 'x-admin-key': process.env.ADMIN_API_KEY };
    assert.equal((await s.api('PATCH', `/api/v1/admin/orders/${id}/status`, { headers: admin, body: { status: 'CONFIRMED' } })).status, 200);
    assert.equal((await s.api('PATCH', `/api/v1/admin/orders/${id}/status`, { headers: admin, body: { status: 'PREPARING' } })).status, 200);
    const late = await s.api('POST', `/api/v1/orders/${id}/cancel`, { token, body: {} });
    assert.equal(late.status, 409);
    const skip = await s.api('PATCH', `/api/v1/admin/orders/${id}/status`, { headers: admin, body: { status: 'DELIVERED' } });
    assert.equal(skip.status, 409);
  });

  test('customers cannot use staff endpoints or see others’ orders', async () => {
    const a = await newUser(s.api);
    const b = await newUser(s.api);
    const address = await addAddress(s.api, a.token);
    await cartWith(a.token, 2);
    const created = await s.api('POST', '/api/v1/orders', { token: a.token, body: { addressId: address.id, paymentMethod: 'CASH_ON_DELIVERY', idempotencyKey: crypto.randomUUID() } });
    assert.equal((await s.api('GET', `/api/v1/orders/${created.body.order.id}`, { token: b.token })).status, 404);
    assert.equal((await s.api('PATCH', `/api/v1/admin/orders/${created.body.order.id}/status`, { token: a.token, body: { status: 'CONFIRMED' } })).status, 403);
  });

  test('empty cart cannot be ordered', async () => {
    const { token } = await newUser(s.api);
    const address = await addAddress(s.api, token);
    const r = await s.api('POST', '/api/v1/orders', { token, body: { addressId: address.id, paymentMethod: 'MOCK', idempotencyKey: crypto.randomUUID() } });
    assert.equal(r.status, 422);
    assert.equal(r.body.error.code, 'CART_INVALID');
  });

  test('reorder puts past items back in the cart', async () => {
    const { token } = await newUser(s.api);
    const address = await addAddress(s.api, token);
    await cartWith(token, 4);
    const created = await s.api('POST', '/api/v1/orders', { token, body: { addressId: address.id, paymentMethod: 'CASH_ON_DELIVERY', idempotencyKey: crypto.randomUUID() } });
    const r = await s.api('POST', `/api/v1/orders/${created.body.order.id}/reorder`, { token });
    assert.equal(r.status, 200);
    assert.equal(r.body.cart.lines[0].quantity, 4);
  });

  test('device token registration and notification preferences', async () => {
    const { token } = await newUser(s.api);
    const reg = await s.api('POST', '/api/v1/notifications/devices', { token, body: { token: 'fcm-token-'.padEnd(40, 'x') } });
    assert.equal(reg.status, 201);
    const prefs = await s.api('PUT', '/api/v1/notifications/preferences', { token, body: { notifyOrderUpdates: false, notifyPromotions: true } });
    assert.deepEqual(prefs.body, { notifyOrderUpdates: false, notifyPromotions: true });
  });
});
