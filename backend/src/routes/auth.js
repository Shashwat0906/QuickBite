'use strict';
const express = require('express');
const crypto = require('node:crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const config = require('../config/env');
const prisma = require('../lib/prisma');
const { validate, z } = require('../lib/validate');
const { asyncHandler, unauthorized, conflict } = require('../lib/errors');
const { requireAuth } = require('../middleware/auth');
const { verifyIdentityToken } = require('../services/socialAuth');
const S = require('../serializers');

const router = express.Router();

const email = z.string().trim().toLowerCase().email('Enter a valid email address');
const password = z
  .string()
  .min(8, 'Password must be at least 8 characters')
  .max(72, 'Password is too long')
  .regex(/[A-Za-z]/, 'Password needs at least one letter')
  .regex(/[0-9]/, 'Password needs at least one number');
const phone = z.string().trim().regex(/^\+?[0-9]{10,13}$/, 'Enter a valid phone number');

const hashToken = (t) => crypto.createHash('sha256').update(t).digest('hex');

/**
 * Access token: short lived JWT (15 min) sent on every request.
 * Refresh token: long lived opaque random string, stored hashed, rotated on use.
 */
async function issueTokens(user) {
  const accessToken = jwt.sign({ sub: user.id, role: user.role }, config.jwt.accessSecret, { expiresIn: config.jwt.accessTtl });
  const refreshToken = crypto.randomBytes(48).toString('base64url');
  await prisma.refreshToken.create({
    data: {
      userId: user.id,
      tokenHash: hashToken(refreshToken),
      expiresAt: new Date(Date.now() + config.jwt.refreshTtlDays * 86400000),
    },
  });
  const { exp } = jwt.decode(accessToken);
  return { accessToken, refreshToken, expiresAt: new Date(exp * 1000).toISOString() };
}

const authResponse = async (user) => ({ user: S.user(user), tokens: await issueTokens(user) });

router.post(
  '/register',
  validate({ body: z.object({ name: z.string().trim().min(2, 'Enter your name').max(60), email, password, phone: phone.optional() }) }),
  asyncHandler(async (req, res) => {
    const { name, email: mail, password: pw, phone: ph } = req.body;
    const existing = await prisma.user.findUnique({ where: { email: mail } });
    if (existing) throw conflict('An account with this email already exists', 'EMAIL_TAKEN');
    const user = await prisma.user.create({
      data: { name, email: mail, phone: ph, passwordHash: await bcrypt.hash(pw, 10), authProvider: 'EMAIL' },
    });
    res.status(201).json(await authResponse(user));
  }),
);

router.post(
  '/login',
  validate({ body: z.object({ email, password: z.string().min(1, 'Enter your password') }) }),
  asyncHandler(async (req, res) => {
    const user = await prisma.user.findUnique({ where: { email: req.body.email } });
    // Same message whether the email or password is wrong (don't leak which accounts exist).
    const ok = user && !user.deletedAt && user.passwordHash && (await bcrypt.compare(req.body.password, user.passwordHash));
    if (!ok) throw Object.assign(unauthorized('Incorrect email or password'), { code: 'INVALID_CREDENTIALS' });
    res.json(await authResponse(user));
  }),
);

router.post(
  '/social',
  validate({
    body: z.object({
      provider: z.enum(['APPLE', 'GOOGLE']),
      identityToken: z.string().min(5),
      // Apple only sends the name on the very first sign-in, so the app forwards it.
      name: z.string().trim().max(60).optional(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { provider, identityToken, name } = req.body;
    const identity = await verifyIdentityToken(provider, identityToken);

    let user = await prisma.user.findUnique({ where: { authProvider_providerSubject: { authProvider: provider, providerSubject: identity.subject } } });
    if (!user && identity.email) {
      // Link to an existing account with the same verified email.
      const byEmail = await prisma.user.findUnique({ where: { email: identity.email.toLowerCase() } });
      if (byEmail && identity.emailVerified && !byEmail.deletedAt) user = byEmail;
    }
    if (!user) {
      if (!identity.email) throw unauthorized('Your Apple ID did not share an email address');
      user = await prisma.user.create({
        data: {
          name: name || identity.name || identity.email.split('@')[0],
          email: identity.email.toLowerCase(),
          authProvider: provider,
          providerSubject: identity.subject,
        },
      });
    }
    if (user.deletedAt) throw unauthorized('This account was deleted');
    res.json({ ...(await authResponse(user)), isDemo: Boolean(identity.isDemo) });
  }),
);

router.post(
  '/refresh',
  validate({ body: z.object({ refreshToken: z.string().min(10) }) }),
  asyncHandler(async (req, res) => {
    const stored = await prisma.refreshToken.findUnique({ where: { tokenHash: hashToken(req.body.refreshToken) }, include: { user: true } });
    if (!stored || stored.expiresAt < new Date() || stored.user.deletedAt) throw unauthorized('Session expired, please sign in again');
    if (stored.revokedAt) {
      // A revoked token was reused → likely stolen. Kill every session for safety.
      await prisma.refreshToken.updateMany({ where: { userId: stored.userId, revokedAt: null }, data: { revokedAt: new Date() } });
      throw unauthorized('Session expired, please sign in again');
    }
    await prisma.refreshToken.update({ where: { id: stored.id }, data: { revokedAt: new Date() } });
    res.json({ tokens: await issueTokens(stored.user) });
  }),
);

router.post(
  '/logout',
  validate({ body: z.object({ refreshToken: z.string().optional(), deviceToken: z.string().optional() }) }),
  asyncHandler(async (req, res) => {
    if (req.body.refreshToken) {
      await prisma.refreshToken.updateMany({ where: { tokenHash: hashToken(req.body.refreshToken), revokedAt: null }, data: { revokedAt: new Date() } });
    }
    if (req.body.deviceToken) await prisma.deviceToken.deleteMany({ where: { token: req.body.deviceToken } });
    res.status(204).end();
  }),
);

// ---- Profile -------------------------------------------------------------

router.get('/me', requireAuth, (req, res) => res.json({ user: S.user(req.user) }));

router.patch(
  '/me',
  requireAuth,
  validate({
    body: z
      .object({
        name: z.string().trim().min(2).max(60).optional(),
        email: email.optional(),
        phone: phone.nullable().optional(),
        notifyOrderUpdates: z.boolean().optional(),
        notifyPromotions: z.boolean().optional(),
      })
      .refine((b) => Object.keys(b).length > 0, 'Nothing to update'),
  }),
  asyncHandler(async (req, res) => {
    if (req.body.email && req.body.email !== req.user.email) {
      const taken = await prisma.user.findUnique({ where: { email: req.body.email } });
      if (taken) throw conflict('That email is already in use', 'EMAIL_TAKEN');
    }
    const user = await prisma.user.update({ where: { id: req.user.id }, data: req.body });
    res.json({ user: S.user(user) });
  }),
);

/**
 * Account deletion (required by App Store guideline 5.1.1(v)).
 * Personal data is anonymised; orders are kept for accounting with no PII.
 */
router.delete(
  '/me',
  requireAuth,
  asyncHandler(async (req, res) => {
    const id = req.user.id;
    await prisma.$transaction([
      prisma.refreshToken.deleteMany({ where: { userId: id } }),
      prisma.deviceToken.deleteMany({ where: { userId: id } }),
      prisma.cart.deleteMany({ where: { userId: id } }),
      prisma.notification.deleteMany({ where: { userId: id } }),
      prisma.address.deleteMany({ where: { userId: id } }),
      prisma.order.updateMany({ where: { userId: id }, data: { deliveryAddress: { redacted: true } } }),
      prisma.user.update({
        where: { id },
        data: { name: 'Deleted user', email: `deleted-${id}@quickbite.invalid`, phone: null, passwordHash: null, providerSubject: null, deletedAt: new Date() },
      }),
    ]);
    res.status(204).end();
  }),
);

module.exports = router;
