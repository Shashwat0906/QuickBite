'use strict';
const http = require('node:http');
const config = require('./config/env');
const prisma = require('./lib/prisma');
const { createApp } = require('./app');
const realtime = require('./realtime/socket');
const demo = require('./services/demoProgression');

const app = createApp();
const server = http.createServer(app);
realtime.attach(server);

server.listen(config.port, () => {
  console.log(`QuickBite API listening on :${config.port} (${config.env})`);
  console.log(`Payments: razorpay=${config.payments.razorpayEnabled} mock=${config.payments.mockEnabled} | push(FCM)=${config.push.fcmEnabled}`);
  demo.start();
});

async function shutdown(signal) {
  console.log(`${signal} received, shutting down`);
  demo.stop();
  await realtime.close();
  server.close(async () => {
    await prisma.$disconnect();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
