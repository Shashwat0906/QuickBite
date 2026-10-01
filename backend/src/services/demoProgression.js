'use strict';
const config = require('../config/env');
const prisma = require('../lib/prisma');
const OS = require('../domain/orderStatus');
const orders = require('./orders');
const realtime = require('../realtime/socket');

/**
 * DEMO ORDER PROGRESSION
 * ----------------------
 * There is no real cafe tablet or rider app in this project, so this worker
 * advances demo orders one status every DEMO_STEP_SECONDS, and broadcasts a
 * *simulated* rider position while an order is out for delivery.
 *
 * It polls the database (instead of in-memory timers) so it survives restarts
 * and works with several server instances. Every order it touches has
 * `isDemoTracking = true`, and the app shows a "Demo tracking" badge.
 */
let timer = null;
let running = false;

async function tick() {
  if (running) return; // never overlap ticks
  running = true;
  try {
    const cutoff = new Date(Date.now() - config.demoStepSeconds * 1000);
    const due = await prisma.order.findMany({
      where: { isDemoTracking: true, status: { in: OS.FLOW.slice(0, -1) }, updatedAt: { lt: cutoff } },
      select: { id: true, status: true },
      take: 50,
    });
    for (const o of due) {
      const next = OS.nextStatus(o.status);
      if (next) await orders.transition(o.id, next, { note: 'Demo progression' }).catch((e) => console.warn('demo step failed', o.id, e.message));
    }

    const riding = await prisma.order.findMany({ where: { isDemoTracking: true, status: 'OUT_FOR_DELIVERY' }, include: { cafe: true, events: true } });
    for (const o of riding) {
      const out = o.events.find((e) => e.status === 'OUT_FOR_DELIVERY');
      const loc = orders.simulatedRiderLocation(o, out?.createdAt);
      if (loc) realtime.emitToOrder(o.id, o.userId, 'order:location', { orderId: o.id, ...loc });
    }
  } catch (e) {
    console.error('demo progression tick failed', e.message);
  } finally {
    running = false;
  }
}

function start() {
  if (!config.demoOrderProgression || timer) return;
  timer = setInterval(tick, 3000);
  timer.unref();
  console.log(`Demo order progression ON (every ${config.demoStepSeconds}s per step)`);
}

function stop() {
  if (timer) clearInterval(timer);
  timer = null;
}

module.exports = { start, stop, tick };
