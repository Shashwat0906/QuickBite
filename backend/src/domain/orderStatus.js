'use strict';
/**
 * Order state machine. Every status change in the system goes through
 * `assertTransition`, so an order can never jump from PLACED to DELIVERED or be
 * cancelled after it has left the cafe.
 *
 * PENDING_PAYMENT exists only for online payments: the order is reserved but the
 * cafe does not see it until the payment is verified on the server.
 */

const FLOW = ['PLACED', 'CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP', 'OUT_FOR_DELIVERY', 'DELIVERED'];

const TRANSITIONS = {
  PENDING_PAYMENT: ['PLACED', 'CANCELLED'],
  PLACED: ['CONFIRMED', 'CANCELLED'],
  CONFIRMED: ['PREPARING', 'CANCELLED'],
  PREPARING: ['READY_FOR_PICKUP'],
  READY_FOR_PICKUP: ['OUT_FOR_DELIVERY'],
  OUT_FOR_DELIVERY: ['DELIVERED'],
  DELIVERED: [],
  CANCELLED: [],
};

/** Customers may cancel only before the kitchen starts cooking. */
const CUSTOMER_CANCELLABLE = new Set(['PENDING_PAYMENT', 'PLACED', 'CONFIRMED']);

const LABELS = {
  PENDING_PAYMENT: 'Awaiting payment',
  PLACED: 'Order placed',
  CONFIRMED: 'Cafe confirmed',
  PREPARING: 'Preparing',
  READY_FOR_PICKUP: 'Ready for pickup',
  OUT_FOR_DELIVERY: 'Out for delivery',
  DELIVERED: 'Delivered',
  CANCELLED: 'Cancelled',
};

/** Push copy for the statuses worth interrupting someone for. */
const NOTIFY = {
  PLACED: { title: 'Order placed ✅', body: 'We have sent order {number} to {cafe}.' },
  CONFIRMED: { title: 'Order confirmed ☕', body: '{cafe} has accepted your order.' },
  PREPARING: { title: 'Being prepared', body: 'Your food is being freshly made.' },
  OUT_FOR_DELIVERY: { title: 'On the way 🛵', body: 'Your order is out for delivery.' },
  DELIVERED: { title: 'Delivered 🎉', body: 'Enjoy your meal! Tap to rate your order.' },
  CANCELLED: { title: 'Order cancelled', body: 'Your order {number} was cancelled.' },
};

function canTransition(from, to) {
  return (TRANSITIONS[from] || []).includes(to);
}

function assertTransition(from, to) {
  if (!canTransition(from, to)) {
    const err = new Error(`Cannot change order status from ${from} to ${to}`);
    err.status = 409;
    err.code = 'INVALID_STATUS_TRANSITION';
    throw err;
  }
}

function nextStatus(current) {
  const i = FLOW.indexOf(current);
  return i >= 0 && i < FLOW.length - 1 ? FLOW[i + 1] : null;
}

function isActive(status) {
  return !['DELIVERED', 'CANCELLED', 'PENDING_PAYMENT'].includes(status);
}

module.exports = { FLOW, TRANSITIONS, LABELS, NOTIFY, CUSTOMER_CANCELLABLE, canTransition, assertTransition, nextStatus, isActive };
