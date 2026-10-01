'use strict';
const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const config = require('../config/env');
const prisma = require('../lib/prisma');

/**
 * Live order updates over Socket.IO.
 *
 * Client connects with `auth: { token: <access JWT> }`, is joined to its private
 * `user:<id>` room, and may `order:subscribe` to orders it owns.
 * Server events:
 *   order:status    { orderId, status, statusLabel, at, estimatedMinutes }
 *   order:location  { orderId, latitude, longitude, isSimulated, at }
 *   notification    { id, title, body, orderId }
 */
let io = null;

function attach(httpServer) {
  io = new Server(httpServer, { cors: { origin: config.corsOrigins }, path: '/socket.io' });

  io.use((socket, next) => {
    try {
      const token = socket.handshake.auth?.token || socket.handshake.headers?.authorization?.replace('Bearer ', '');
      const payload = jwt.verify(token, config.jwt.accessSecret);
      socket.data.userId = payload.sub;
      next();
    } catch {
      next(new Error('UNAUTHORIZED'));
    }
  });

  io.on('connection', (socket) => {
    socket.join(`user:${socket.data.userId}`);

    socket.on('order:subscribe', async (orderId, ack) => {
      const reply = typeof ack === 'function' ? ack : () => {};
      if (typeof orderId !== 'string') return reply({ ok: false, error: 'BAD_ORDER_ID' });
      try {
        const order = await prisma.order.findFirst({ where: { id: orderId, userId: socket.data.userId }, select: { id: true, status: true } });
        if (!order) return reply({ ok: false, error: 'NOT_FOUND' });
        socket.join(`order:${orderId}`);
        reply({ ok: true, status: order.status });
      } catch {
        reply({ ok: false, error: 'BAD_ORDER_ID' });
      }
    });

    socket.on('order:unsubscribe', (orderId) => socket.leave(`order:${orderId}`));
  });

  return io;
}

function emitToOrder(orderId, userId, event, payload) {
  if (!io) return;
  // Both rooms: the order screen (subscribed) and any other screen of that user.
  io.to(`order:${orderId}`).to(`user:${userId}`).emit(event, payload);
}

function emitToUser(userId, event, payload) {
  if (io) io.to(`user:${userId}`).emit(event, payload);
}

function close() {
  return new Promise((resolve) => (io ? io.close(() => resolve()) : resolve()));
}

module.exports = { attach, emitToOrder, emitToUser, close };
