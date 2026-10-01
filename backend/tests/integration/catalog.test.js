'use strict';
const { test, describe, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, newUser, openCafeItem, prisma } = require('./helpers');

let s;
before(async () => { s = await startServer(); });
after(async () => { await s.stop(); await prisma.$disconnect(); });

describe('catalogue API', () => {
  test('home feed has cafes, dishes and offers', async () => {
    const r = await s.api('GET', '/api/v1/home');
    assert.equal(r.status, 200);
    assert.ok(r.body.nearbyCafes.length >= 5);
    assert.ok(r.body.featuredCafes.every((c) => c.isFeatured));
    assert.ok(r.body.popularDishes.length > 0);
    assert.ok(r.body.offers.some((o) => o.code === 'WELCOME50'));
    assert.ok(!r.body.offers.some((o) => o.code === 'MONSOON20'), 'expired coupon must not be advertised');
    // Sorted by distance
    const d = r.body.nearbyCafes.map((c) => c.distanceKm);
    assert.deepEqual(d, [...d].sort((a, b) => a - b));
  });

  test('cafe list filters by rating and paginates', async () => {
    const r = await s.api('GET', '/api/v1/cafes?minRating=4.5&limit=2');
    assert.equal(r.status, 200);
    assert.ok(r.body.cafes.length <= 2);
    assert.ok(r.body.cafes.every((c) => c.rating >= 4.5));
    assert.equal(r.body.meta.limit, 2);
  });

  test('cafe detail returns a menu with customizations', async () => {
    const { cafe } = await openCafeItem();
    const r = await s.api('GET', `/api/v1/cafes/${cafe.id}`);
    assert.equal(r.status, 200);
    assert.ok(r.body.menu.length > 0);
    const chai = r.body.menu.flatMap((c) => c.items).find((i) => i.name === 'Masala Chai');
    assert.equal(chai.customizations[0].name, 'Size');
  });

  test('unknown cafe → 404, malformed id → 400', async () => {
    assert.equal((await s.api('GET', '/api/v1/cafes/00000000-0000-4000-8000-000000000000')).status, 404);
    assert.equal((await s.api('GET', '/api/v1/cafes/not-a-uuid')).status, 400);
  });

  test('search matches dishes and cafes, case-insensitive', async () => {
    const r = await s.api('GET', '/api/v1/search?q=LATTE');
    assert.equal(r.status, 200);
    assert.ok(r.body.items.length > 0);
    assert.ok(r.body.items.every((i) => /latte/i.test(i.name + i.description + (i.cafeName || ''))));
  });

  test('search veg filter + price sort', async () => {
    const r = await s.api('GET', '/api/v1/search?veg=true&sort=priceLow&limit=50');
    const prices = r.body.items.map((i) => i.pricePaise);
    assert.deepEqual(prices, [...prices].sort((a, b) => a - b));
    assert.ok(r.body.items.every((i) => i.diet === 'VEG'));
  });

  test('sold-out items are reported unavailable', async () => {
    const r = await s.api('GET', '/api/v1/search?q=Almond Croissant');
    const item = r.body.items.find((i) => i.name === 'Almond Croissant');
    assert.equal(item.isAvailable, false);
  });

  test('cafe reviews endpoint returns a distribution', async () => {
    const { cafe } = await openCafeItem();
    const r = await s.api('GET', `/api/v1/cafes/${cafe.id}/reviews`);
    assert.equal(r.status, 200);
    assert.deepEqual(Object.keys(r.body.distribution), ['1', '2', '3', '4', '5']);
  });

  test('addresses: first is default, PIN validated', async () => {
    const { token } = await newUser(s.api);
    const bad = await s.api('POST', '/api/v1/addresses', { token, body: { label: 'X', line1: 'abc st', city: 'Delhi', pincode: '12', latitude: 1, longitude: 1 } });
    assert.equal(bad.status, 400);
    const a = await s.api('POST', '/api/v1/addresses', { token, body: { label: 'Home', line1: '1 Main St', city: 'Delhi', pincode: '110001', latitude: 28.6, longitude: 77.2 } });
    assert.equal(a.body.address.isDefault, true);
    const b = await s.api('POST', '/api/v1/addresses', { token, body: { label: 'Work', line1: '2 Main St', city: 'Delhi', pincode: '110002', latitude: 28.6, longitude: 77.2, isDefault: true } });
    const list = await s.api('GET', '/api/v1/addresses', { token });
    assert.equal(list.body.addresses.filter((x) => x.isDefault).length, 1);
    assert.equal(list.body.addresses[0].id, b.body.address.id);
  });
});
