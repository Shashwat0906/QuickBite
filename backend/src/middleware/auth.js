'use strict';
const jwt = require('jsonwebtoken');
const config = require('../config/env');
const prisma = require('../lib/prisma');
const { unauthorized, forbidden } = require('../lib/errors');

/** Requires a valid `Authorization: Bearer <access token>`; sets req.user. */
async function requireAuth(req, _res, next) {
  try {
    const header = req.headers.authorization || '';
    const [scheme, token] = header.split(' ');
    if (scheme !== 'Bearer' || !token) throw unauthorized('Missing access token');
    let payload;
    try {
      payload = jwt.verify(token, config.jwt.accessSecret);
    } catch (e) {
      throw e.name === 'TokenExpiredError'
        ? Object.assign(unauthorized('Access token expired'), { code: 'TOKEN_EXPIRED' })
        : unauthorized('Invalid access token');
    }
    const user = await prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user || user.deletedAt) throw unauthorized('Account not found');
    req.user = user;
    next();
  } catch (err) {
    next(err);
  }
}

/** Same as requireAuth but lets guests through (req.user stays undefined). */
async function optionalAuth(req, res, next) {
  if (!req.headers.authorization) return next();
  return requireAuth(req, res, next);
}

/**
 * Staff/admin gate for operations customers must never perform (moving an order
 * to PREPARING etc.). Accepts a signed-in ADMIN/CAFE_STAFF user or the
 * ADMIN_API_KEY header for demos.
 */
async function requireStaff(req, res, next) {
  const key = req.headers['x-admin-key'];
  if (config.adminApiKey && key && key === config.adminApiKey) {
    req.staff = { via: 'api-key' };
    return next();
  }
  return requireAuth(req, res, (err) => {
    if (err) return next(err);
    if (!['ADMIN', 'CAFE_STAFF'].includes(req.user.role)) return next(forbidden());
    req.staff = { via: 'user', userId: req.user.id };
    next();
  });
}

module.exports = { requireAuth, optionalAuth, requireStaff };
