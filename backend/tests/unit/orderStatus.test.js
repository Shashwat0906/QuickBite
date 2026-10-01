'use strict';
const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const S = require('../../src/domain/orderStatus');
const { verifySignature, expectedSignature, verifyWebhook } = require('../../src/domain/paymentSignature');
const crypto = require('node:crypto');

describe('order state machine', () => {
  test('happy path walks every step in order', () => {
    let s = 'PLACED';
    const seen = [s];
    while ((s = S.nextStatus(s))) seen.push(s);
    assert.deepEqual(seen, S.FLOW);
  });
  test('cannot skip steps', () => assert.throws(() => S.assertTransition('PLACED', 'DELIVERED'), /Cannot change/));
  test('cannot cancel once preparing', () => assert.equal(S.canTransition('PREPARING', 'CANCELLED'), false));
  test('can cancel before preparing', () => assert.equal(S.canTransition('CONFIRMED', 'CANCELLED'), true));
  test('unpaid orders can only be placed or cancelled', () => {
    assert.deepEqual(S.TRANSITIONS.PENDING_PAYMENT, ['PLACED', 'CANCELLED']);
    assert.equal(S.isActive('PENDING_PAYMENT'), false);
  });
  test('terminal states have no exits', () => {
    assert.equal(S.nextStatus('DELIVERED'), null);
    assert.deepEqual(S.TRANSITIONS.CANCELLED, []);
  });
  test('invalid transition error carries HTTP 409', () => {
    try { S.assertTransition('DELIVERED', 'PLACED'); } catch (e) { assert.equal(e.status, 409); return; }
    assert.fail('expected throw');
  });
});

describe('razorpay signature', () => {
  const secret = 'test_secret';
  test('accepts a correct signature', () => {
    const signature = expectedSignature('order_1', 'pay_1', secret);
    assert.equal(verifySignature({ orderId: 'order_1', paymentId: 'pay_1', signature, secret }), true);
  });
  test('rejects a tampered payment id', () => {
    const signature = expectedSignature('order_1', 'pay_1', secret);
    assert.equal(verifySignature({ orderId: 'order_1', paymentId: 'pay_2', signature, secret }), false);
  });
  test('rejects missing pieces', () => assert.equal(verifySignature({ orderId: 'o', paymentId: 'p', signature: '', secret }), false));
  test('webhook signature over raw body', () => {
    const body = '{"event":"payment.captured"}';
    const sig = crypto.createHmac('sha256', 'wh').update(body).digest('hex');
    assert.equal(verifyWebhook(body, sig, 'wh'), true);
    assert.equal(verifyWebhook(body + ' ', sig, 'wh'), false);
  });
});
