'use strict';
const express = require('express');
const prisma = require('../lib/prisma');
const { validate, z, uuid, pagination, paginate, pageMeta } = require('../lib/validate');
const { asyncHandler } = require('../lib/errors');
const { requireAuth } = require('../middleware/auth');
const S = require('../serializers');
const config = require('../config/env');

const router = express.Router();
router.use(requireAuth);

/** Register (or move) an FCM registration token to the signed-in user. */
router.post(
  '/devices',
  validate({ body: z.object({ token: z.string().min(20).max(4096), platform: z.enum(['IOS', 'ANDROID']).default('IOS') }) }),
  asyncHandler(async (req, res) => {
    // A token belongs to one device; if another user signed in on it, reassign.
    await prisma.deviceToken.upsert({
      where: { token: req.body.token },
      create: { token: req.body.token, platform: req.body.platform, userId: req.user.id },
      update: { userId: req.user.id, platform: req.body.platform },
    });
    res.status(201).json({ registered: true, pushEnabledOnServer: config.push.fcmEnabled });
  }),
);

router.delete('/devices/:token', asyncHandler(async (req, res) => {
  await prisma.deviceToken.deleteMany({ where: { token: req.params.token, userId: req.user.id } });
  res.status(204).end();
}));

router.get('/', validate({ query: pagination }), asyncHandler(async (req, res) => {
  const where = { userId: req.user.id };
  const [list, total, unread] = await Promise.all([
    prisma.notification.findMany({ where, orderBy: { createdAt: 'desc' }, ...paginate(req.query) }),
    prisma.notification.count({ where }),
    prisma.notification.count({ where: { ...where, isRead: false } }),
  ]);
  res.json({ notifications: list.map(S.notification), unreadCount: unread, meta: pageMeta(req.query, total) });
}));

router.post('/read', validate({ body: z.object({ ids: z.array(uuid).max(100).optional() }) }), asyncHandler(async (req, res) => {
  await prisma.notification.updateMany({
    where: { userId: req.user.id, ...(req.body.ids ? { id: { in: req.body.ids } } : {}) },
    data: { isRead: true },
  });
  res.status(204).end();
}));

router.get('/preferences', (req, res) => res.json({ notifyOrderUpdates: req.user.notifyOrderUpdates, notifyPromotions: req.user.notifyPromotions }));

router.put(
  '/preferences',
  validate({ body: z.object({ notifyOrderUpdates: z.boolean(), notifyPromotions: z.boolean() }) }),
  asyncHandler(async (req, res) => {
    const u = await prisma.user.update({ where: { id: req.user.id }, data: req.body });
    res.json({ notifyOrderUpdates: u.notifyOrderUpdates, notifyPromotions: u.notifyPromotions });
  }),
);

module.exports = router;
