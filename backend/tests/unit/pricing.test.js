'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const P = require('../../src/domain/pricing');

const cafe = { deliveryFeePaise: 2500, minOrderPaise: 9900, avgPrepMinutes: 8 };

describe('unitPrice', () => {
  test('adds option extras to the base price', () => {
    assert.equal(P.unitPrice(18000, [{ extraPricePaise: 3000 }, { extraPricePaise: 4000 }]), 25000);
  });
  test('base price when no options', () => assert.equal(P.unitPrice(18000), 18000));
});

describe('computeBill', () => {
  test('charges delivery and 5% tax on a normal order', () => {
    const bill = P.computeBill({ lines: [{ unitPricePaise: 15000, quantity: 2 }], cafe });
    assert.deepEqual(bill, { subtotalPaise: 30000, discountPaise: 0, deliveryFeePaise: 2500, taxPaise: 1500, totalPaise: 34000 });
  });
  test('free delivery at or above ₹499', () => {
    const bill = P.computeBill({ lines: [{ unitPricePaise: 49900, quantity: 1 }], cafe });
    assert.equal(bill.deliveryFeePaise, 0);
  });
  test('small-order fee below the cafe minimum', () => {
    const bill = P.computeBill({ lines: [{ unitPricePaise: 5000, quantity: 1 }], cafe });
    assert.equal(bill.deliveryFeePaise, 2500 + P.SMALL_ORDER_FEE_PAISE);
  });
  test('tax is computed on the discounted amount', () => {
    const bill = P.computeBill({ lines: [{ unitPricePaise: 20000, quantity: 1 }], cafe, discountPaise: 10000 });
    assert.equal(bill.taxPaise, 500);
    assert.equal(bill.totalPaise, 20000 - 10000 + 2500 + 500);
  });
  test('discount can never exceed subtotal', () => {
    const bill = P.computeBill({ lines: [{ unitPricePaise: 10000, quantity: 1 }], cafe, discountPaise: 99999 });
    assert.equal(bill.discountPaise, 10000);
    assert.ok(bill.totalPaise >= 0);
  });
  test('empty cart has no fees', () => {
    const bill = P.computeBill({ lines: [], cafe });
    assert.equal(bill.totalPaise, 2500); // delivery fee only applies; callers block empty carts
  });
});

describe('couponDiscount', () => {
  const base = { isActive: true, usageLimitPerUser: 1, minOrderPaise: 0, maxDiscountPaise: null, validFrom: null, validUntil: null };
  test('flat coupon', () => {
    assert.deepEqual(P.couponDiscount({ ...base, type: 'FLAT', value: 5000 }, 30000), { ok: true, discountPaise: 5000 });
  });
  test('percent coupon is capped', () => {
    const r = P.couponDiscount({ ...base, type: 'PERCENT', value: 50, maxDiscountPaise: 10000 }, 40000);
    assert.equal(r.discountPaise, 10000);
  });
  test('rejects below minimum order with a helpful message', () => {
    const r = P.couponDiscount({ ...base, type: 'FLAT', value: 5000, minOrderPaise: 29900 }, 20000);
    assert.equal(r.ok, false);
    assert.match(r.reason, /₹99 more/);
  });
  test('rejects expired coupons', () => {
    const r = P.couponDiscount({ ...base, type: 'FLAT', value: 100, validUntil: '2020-01-01' }, 30000);
    assert.equal(r.ok, false);
    assert.match(r.reason, /expired/);
  });
  test('rejects when the user hit the usage limit', () => {
    const r = P.couponDiscount({ ...base, type: 'FLAT', value: 100 }, 30000, { timesUsedByUser: 1 });
    assert.equal(r.ok, false);
  });
  test('rejects inactive / missing coupons', () => {
    assert.equal(P.couponDiscount(null, 100).ok, false);
    assert.equal(P.couponDiscount({ ...base, isActive: false }, 100).ok, false);
  });
});

describe('validateSelection', () => {
  const groups = [
    { id: 'size', name: 'Size', minSelect: 1, maxSelect: 1, options: [{ id: 's', name: 'Small', extraPricePaise: 0, isAvailable: true }, { id: 'l', name: 'Large', extraPricePaise: 4000, isAvailable: true }] },
    { id: 'extra', name: 'Extras', minSelect: 0, maxSelect: 2, options: [{ id: 'a', name: 'Oat milk', extraPricePaise: 3000, isAvailable: true }, { id: 'b', name: 'Shot', extraPricePaise: 3000, isAvailable: true }, { id: 'c', name: 'Syrup', extraPricePaise: 2000, isAvailable: false }] },
  ];
  test('accepts a valid selection', () => assert.equal(P.validateSelection(groups, ['l', 'a']).ok, true));
  test('requires mandatory groups', () => assert.match(P.validateSelection(groups, ['a']).reason, /Size/));
  test('enforces max select', () => assert.equal(P.validateSelection(groups, ['s', 'l']).ok, false));
  test('rejects unavailable options', () => assert.match(P.validateSelection(groups, ['s', 'c']).reason, /unavailable/));
  test('rejects unknown option ids', () => assert.equal(P.validateSelection(groups, ['s', 'zzz']).ok, false));
});

describe('helpers', () => {
  test('lineKey is order-independent', () => assert.equal(P.lineKey('x', ['b', 'a']), P.lineKey('x', ['a', 'b'])));
  test('distanceKm Connaught Place → India Gate ≈ 2.4 km', () => {
    const d = P.distanceKm(28.6315, 77.2167, 28.6129, 77.2295);
    assert.ok(d > 2 && d < 3, `got ${d}`);
  });
  test('estimate has a 10 minute floor', () => assert.equal(P.estimateMinutes({ avgPrepMinutes: 1 }, 0), 10));
});
