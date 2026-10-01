'use strict';
/**
 * Central configuration. Every secret comes from the environment — nothing is
 * hard-coded. Missing optional integrations switch that feature into a clearly
 * labelled demo/mock mode instead of crashing.
 */
require('dotenv').config();

function required(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required environment variable ${name}. See backend/.env.example`);
  return v;
}

const env = process.env.NODE_ENV || 'development';

const config = {
  env,
  isProd: env === 'production',
  isTest: env === 'test',
  port: Number(process.env.PORT || 4000),
  databaseUrl: required('DATABASE_URL'),
  corsOrigins: (process.env.CORS_ORIGINS || '*').split(',').map((s) => s.trim()),

  jwt: {
    accessSecret: required('JWT_ACCESS_SECRET'),
    refreshSecret: required('JWT_REFRESH_SECRET'),
    accessTtl: process.env.JWT_ACCESS_TTL || '15m',
    refreshTtlDays: Number(process.env.JWT_REFRESH_TTL_DAYS || 30),
  },

  razorpay: {
    keyId: process.env.RAZORPAY_KEY_ID || '',
    keySecret: process.env.RAZORPAY_KEY_SECRET || '',
    webhookSecret: process.env.RAZORPAY_WEBHOOK_SECRET || '',
  },

  social: {
    appleBundleId: process.env.APPLE_BUNDLE_ID || '',
    googleClientIds: (process.env.GOOGLE_CLIENT_IDS || '').split(',').map((s) => s.trim()).filter(Boolean),
    // When true, /auth/apple and /auth/google accept "demo:<email>" tokens.
    // Never enable this in a real production deployment.
    allowDemo: process.env.SOCIAL_LOGIN_DEMO === 'true',
  },

  fcm: {
    projectId: process.env.FCM_PROJECT_ID || '',
    clientEmail: process.env.FCM_CLIENT_EMAIL || '',
    privateKey: (process.env.FCM_PRIVATE_KEY || '').replace(/\\n/g, '\n'),
  },

  // Demo order progression: advances PLACED → DELIVERED on a timer so the
  // tracking screen can be demonstrated without a real cafe/rider app.
  demoOrderProgression: process.env.DEMO_ORDER_PROGRESSION !== 'false',
  demoStepSeconds: Number(process.env.DEMO_STEP_SECONDS || 20),

  // Lets the admin / cafe-staff status endpoint be used from curl in demos.
  adminApiKey: process.env.ADMIN_API_KEY || '',
};

config.payments = {
  razorpayEnabled: Boolean(config.razorpay.keyId && config.razorpay.keySecret),
  mockEnabled: process.env.MOCK_PAYMENTS !== 'false',
};
config.push = { fcmEnabled: Boolean(config.fcm.projectId && config.fcm.clientEmail && config.fcm.privateKey) };

module.exports = config;
