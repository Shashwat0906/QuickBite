#!/usr/bin/env node
'use strict';
/**
 * End-to-end smoke test against a deployed QuickBite API.
 *   node scripts/smoke-test.js https://quickbite-api-0zul.onrender.com
 *
 * Registers a throwaway user, adds an address, fills the cart, places an order
 * with the demo payment provider, pays, then waits for live status updates over
 * Socket.IO (requires DEMO_ORDER_PROGRESSION on the server).
 */
const { io } = require('socket.io-client');

const base = (process.argv[2] || process.env.API_URL || 'http://localhost:4000').replace(/\/$/, '');
const api = `${base}/api/v1`;
const results = [];

function check(name, ok, detail = '') {
  results.push({ name, ok });
  console.log(`${ok ? '✅' : '❌'} ${name}${detail ? ` — ${detail}` : ''}`);
  if (!ok) throw new Error(`Failed: ${name}`);
}

async function call(method, path, { token, body } = {}) {
  const res = await fetch(`${api}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

(async () => {
  // Free Render instances sleep — the first request can take ~60 s.
  const started = Date.now();
  const health = await fetch(`${base}/health`).then((r) => r.json());
  check('health', health.status === 'ok' && health.database === 'ok', `${JSON.stringify(health.features)} (${Date.now() - started} ms)`);

  const home = await call('GET', '/home');
  check('home feed', home.status === 200 && home.body.nearbyCafes.length >= 5, `${home.body.nearbyCafes.length} cafés, ${home.body.offers.length} offers`);

  const search = await call('GET', '/search?q=latte');
  check('search', search.status === 200 && search.body.items.length > 0, `${search.body.items.length} results for "latte"`);

  const email = `smoke-${Date.now()}@quickbite.test`;
  const reg = await call('POST', '/auth/register', { body: { name: 'Smoke Test', email, password: 'Smoke12345' } });
  check('register', reg.status === 201);
  const token = reg.body.tokens.accessToken;

  const addr = await call('POST', '/addresses', { token, body: { label: 'Home', line1: 'B-12 Barakhamba Road', city: 'New Delhi', pincode: '110001', latitude: 28.629, longitude: 77.225 } });
  check('add address', addr.status === 201);

  const cafe = home.body.nearbyCafes.find((c) => c.isOpenNow);
  const detail = await call('GET', `/cafes/${cafe.id}`);
  const item = detail.body.menu.flatMap((s) => s.items).find((i) => i.isAvailable && i.customizations.length === 0);
  const cart = await call('PUT', '/cart', { token, body: { items: [{ menuItemId: item.id, quantity: 3, optionIds: [] }], couponCode: 'WELCOME50' } });
  check('cart priced by server', cart.status === 200 && cart.body.cart.canCheckout, `${cafe.name}: 3 × ${item.name}, total ₹${cart.body.cart.bill.totalPaise / 100}, coupon ${cart.body.cart.coupon?.isValid ? 'applied' : cart.body.cart.coupon?.message}`);

  const key = `smoke-${Date.now()}`;
  const order = await call('POST', '/orders', { token, body: { addressId: addr.body.address.id, paymentMethod: 'MOCK', idempotencyKey: key } });
  check('order created (pending payment)', order.status === 201 && order.body.order.status === 'PENDING_PAYMENT', order.body.order.orderNumber);
  const replay = await call('POST', '/orders', { token, body: { addressId: addr.body.address.id, paymentMethod: 'MOCK', idempotencyKey: key } });
  check('idempotent retry returns same order', replay.status === 200 && replay.body.order.id === order.body.order.id);

  // Subscribe to live updates before paying.
  const statuses = [];
  const socket = io(base, { auth: { token }, transports: ['websocket'] });
  await new Promise((resolve, reject) => {
    socket.on('connect', () => socket.emit('order:subscribe', order.body.order.id, (ack) => (ack.ok ? resolve() : reject(new Error('subscribe failed')))));
    socket.on('connect_error', reject);
    setTimeout(() => reject(new Error('socket timeout')), 20000);
  });
  check('socket connected + subscribed', true);
  socket.on('order:status', (e) => statuses.push(e.status));

  const paid = await call('POST', `/payments/${order.body.payment.id}/mock-complete`, { token, body: { outcome: 'success' } });
  check('demo payment → PLACED', paid.body.order.status === 'PLACED');

  // Wait for the demo worker to advance the order (DEMO_STEP_SECONDS on the server).
  const flow = ['PLACED', 'CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP', 'OUT_FOR_DELIVERY', 'DELIVERED'];
  const deadline = Date.now() + 90000;
  while (Date.now() < deadline && statuses.filter((s) => s !== 'PLACED').length < 2) await new Promise((r) => setTimeout(r, 1000));
  socket.close();
  const indexes = statuses.map((s) => flow.indexOf(s));
  const inOrder = indexes.every((v, i) => i === 0 || v > indexes[i - 1]);
  check('live status updates over Socket.IO (in order)', statuses.filter((s) => s !== 'PLACED').length >= 2 && inOrder, `received: ${statuses.join(' → ')}`);

  const tracking = await call('GET', `/orders/${order.body.order.id}/tracking`, { token });
  check('tracking snapshot', tracking.status === 200 && tracking.body.isDemoTracking === true, `status ${tracking.body.status}, ETA ${tracking.body.estimatedMinutes} min`);

  const del = await call('DELETE', '/auth/me', { token });
  check('cleanup: delete smoke account', del.status === 204);

  console.log(`\nAll ${results.length} checks passed against ${base}`);
  process.exit(0);
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
