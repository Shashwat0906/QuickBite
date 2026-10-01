'use strict';
const jwt = require('jsonwebtoken');
const config = require('../config/env');
const prisma = require('../lib/prisma');
const realtime = require('../realtime/socket');

/**
 * Notifications are always stored in the database (in-app inbox + realtime
 * event). If FCM credentials are configured they are also sent as push
 * notifications via the FCM HTTP v1 API. Without credentials, push is skipped
 * and `pushSent` stays false — the in-app inbox is the fallback.
 */

let cachedAccessToken = null; // { token, expiresAt }

/** OAuth2 access token for FCM from the service account (JWT bearer grant). */
async function fcmAccessToken() {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60000) return cachedAccessToken.token;
  const now = Math.floor(Date.now() / 1000);
  const assertion = jwt.sign(
    { iss: config.fcm.clientEmail, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 },
    config.fcm.privateKey,
    { algorithm: 'RS256' },
  );
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  if (!res.ok) throw new Error(`FCM auth failed: ${res.status}`);
  const json = await res.json();
  cachedAccessToken = { token: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
  return cachedAccessToken.token;
}

async function sendPush(tokens, { title, body, data }) {
  if (!config.push.fcmEnabled || tokens.length === 0) return false;
  const accessToken = await fcmAccessToken();
  let anySent = false;
  await Promise.all(tokens.map(async (t) => {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${config.fcm.projectId}/messages:send`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: {
          token: t.token,
          notification: { title, body },
          data: Object.fromEntries(Object.entries(data || {}).map(([k, v]) => [k, String(v)])),
          apns: { payload: { aps: { sound: 'default' } } },
        },
      }),
    });
    if (res.ok) anySent = true;
    else if (res.status === 404 || res.status === 400) {
      // Token is no longer valid (app uninstalled etc.) — clean it up.
      await prisma.deviceToken.deleteMany({ where: { token: t.token } });
    } else console.warn('FCM send failed', res.status, await res.text());
  }));
  return anySent;
}

/** Create + deliver a notification. Never throws — notifications must not break orders. */
async function notifyUser(userId, { title, body, orderId, kind = 'ORDER' }) {
  try {
    const user = await prisma.user.findUnique({ where: { id: userId }, include: { devices: true } });
    if (!user) return null;
    if (kind === 'ORDER' && !user.notifyOrderUpdates) return null;
    if (kind === 'PROMO' && !user.notifyPromotions) return null;

    const n = await prisma.notification.create({ data: { userId, title, body, orderId } });
    realtime.emitToUser(userId, 'notification', { id: n.id, title, body, orderId, createdAt: n.createdAt });
    const pushed = await sendPush(user.devices, { title, body, data: orderId ? { orderId, type: 'order' } : {} }).catch((e) => {
      console.warn('push failed:', e.message);
      return false;
    });
    if (pushed) await prisma.notification.update({ where: { id: n.id }, data: { pushSent: true } });
    return n;
  } catch (e) {
    console.error('notifyUser failed', e);
    return null;
  }
}

module.exports = { notifyUser, sendPush };
