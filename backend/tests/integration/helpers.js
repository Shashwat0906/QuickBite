'use strict';
/**
 * Integration test harness: boots the real Express app + Socket.IO on a random
 * port against a real PostgreSQL database (see `npm run test:prepare`).
 */
process.env.NODE_ENV = 'test';
process.env.DEMO_ORDER_PROGRESSION = 'false';
process.env.DEMO_STEP_SECONDS = '0';
process.env.SOCIAL_LOGIN_DEMO = 'true';
process.env.MOCK_PAYMENTS = 'true';
process.env.JWT_ACCESS_SECRET ||= 'test-access-secret';
process.env.JWT_REFRESH_SECRET ||= 'test-refresh-secret';
process.env.RAZORPAY_KEY_SECRET ||= 'rzp_test_secret_for_signature_tests';
process.env.ADMIN_API_KEY ||= 'test-admin-key';

const http = require('node:http');
const crypto = require('node:crypto');
const { createApp } = require('../../src/app');
const realtime = require('../../src/realtime/socket');
const prisma = require('../../src/lib/prisma');

async function startServer() {
  const server = http.createServer(createApp());
  realtime.attach(server);
  await new Promise((r) => server.listen(0, r));
  const base = `http://127.0.0.1:${server.address().port}`;

  async function api(method, path, { token, body, headers } = {}) {
    const res = await fetch(`${base}${path}`, {
      method,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    return { status: res.status, body: text ? JSON.parse(text) : null };
  }

  async function stop() {
    await realtime.close();
    await new Promise((r) => server.close(r));
  }
  return { base, api, stop };
}

/** Registers a fresh user and returns { token, refreshToken, user }. */
async function newUser(api, overrides = {}) {
  const email = `user-${crypto.randomBytes(5).toString('hex')}@test.dev`;
  const res = await api('POST', '/api/v1/auth/register', { body: { name: 'Test User', email, password: 'Passw0rd!', ...overrides } });
  if (res.status !== 201) throw new Error(`register failed ${res.status} ${JSON.stringify(res.body)}`);
  return { token: res.body.tokens.accessToken, refreshToken: res.body.tokens.refreshToken, user: res.body.user, email };
}

async function addAddress(api, token) {
  const res = await api('POST', '/api/v1/addresses', {
    token,
    body: { label: 'Home', line1: '12 Barakhamba Road', city: 'New Delhi', pincode: '110001', latitude: 28.629, longitude: 77.225 },
  });
  return res.body.address;
}

/** An always-open cafe from the seed (Chai Chowk, 00:00–23:59). */
async function openCafeItem({ withCustomizations = false } = {}) {
  const cafe = await prisma.cafe.findUnique({ where: { slug: 'chai-chowk' } });
  const item = await prisma.menuItem.findFirst({
    where: { cafeId: cafe.id, customizations: withCustomizations ? { some: {} } : { none: {} } },
    include: { customizations: { include: { options: true } } },
  });
  return { cafe, item };
}

module.exports = { startServer, newUser, addAddress, openCafeItem, prisma };
