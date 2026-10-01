'use strict';
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const config = require('./config/env');
const prisma = require('./lib/prisma');
const { notFoundHandler, errorHandler } = require('./middleware/error');
const payments = require('./routes/payments');

/** Builds the Express app (no listening) so tests can mount it on any port. */
function createApp() {
  const app = express();
  app.set('trust proxy', 1); // behind Render's / any HTTPS load balancer
  app.disable('x-powered-by');
  app.use(helmet());
  app.use(cors({ origin: config.corsOrigins.includes('*') ? true : config.corsOrigins }));
  if (!config.isTest) app.use(morgan(config.isProd ? 'combined' : 'dev'));

  // Webhook needs the raw body for signature verification — mount before express.json().
  app.post('/api/v1/payments/webhook/razorpay', express.raw({ type: 'application/json', limit: '1mb' }), payments.webhook);

  app.use(express.json({ limit: '100kb' }));

  // Health check for the hosting provider and the app's "server status" row.
  app.get('/health', async (_req, res) => {
    let db = 'ok';
    try { await prisma.$queryRaw`SELECT 1`; } catch { db = 'down'; }
    res.status(db === 'ok' ? 200 : 503).json({
      status: db === 'ok' ? 'ok' : 'degraded',
      database: db,
      version: process.env.RENDER_GIT_COMMIT?.slice(0, 7) || process.env.npm_package_version || 'dev',
      features: {
        razorpay: config.payments.razorpayEnabled,
        mockPayments: config.payments.mockEnabled,
        fcm: config.push.fcmEnabled,
        demoOrderProgression: config.demoOrderProgression,
        socialLoginDemo: config.social.allowDemo,
      },
      time: new Date().toISOString(),
    });
  });

  const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: config.isTest ? 10000 : 50, standardHeaders: 'draft-7', legacyHeaders: false,
    message: { error: { code: 'RATE_LIMITED', message: 'Too many attempts, try again in a few minutes' } } });
  const apiLimiter = rateLimit({ windowMs: 60 * 1000, limit: config.isTest ? 100000 : 300, standardHeaders: 'draft-7', legacyHeaders: false,
    message: { error: { code: 'RATE_LIMITED', message: 'Too many requests, slow down a little' } } });

  const v1 = express.Router();
  v1.use(apiLimiter);
  v1.use('/auth', authLimiter, require('./routes/auth'));
  v1.use('/addresses', require('./routes/addresses'));
  v1.use('/', require('./routes/catalog'));
  v1.use('/cart', require('./routes/cart'));
  v1.use('/orders', require('./routes/orders'));
  v1.use('/payments', payments.router);
  v1.use('/', require('./routes/reviews'));
  v1.use('/notifications', require('./routes/notifications'));
  v1.use('/admin', require('./routes/admin'));
  app.use('/api/v1', v1);

  app.get('/', (_req, res) => res.json({ name: 'QuickBite API', docs: 'https://github.com/ (see docs/API.md)', health: '/health' }));

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}

module.exports = { createApp };
