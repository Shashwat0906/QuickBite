'use strict';
const crypto = require('node:crypto');
const config = require('../config/env');
const { unauthorized } = require('../lib/errors');

/**
 * Verifies Sign in with Apple / Google identity tokens (JWTs signed with the
 * provider's rotating RSA keys, published as JWKS).
 *
 * Demo mode (SOCIAL_LOGIN_DEMO=true): tokens of the form "demo:<email>" are
 * accepted so the flow can be shown without paid Apple developer setup. The iOS
 * app labels this clearly as "Demo sign-in".
 */

const PROVIDERS = {
  APPLE: { jwks: 'https://appleid.apple.com/auth/keys', issuers: ['https://appleid.apple.com'] },
  GOOGLE: { jwks: 'https://www.googleapis.com/oauth2/v3/certs', issuers: ['https://accounts.google.com', 'accounts.google.com'] },
};

const keyCache = new Map(); // provider -> { keys, fetchedAt }

async function getKeys(provider, { forceRefresh = false } = {}) {
  const cached = keyCache.get(provider);
  if (!forceRefresh && cached && Date.now() - cached.fetchedAt < 60 * 60 * 1000) return cached.keys;
  const res = await fetch(PROVIDERS[provider].jwks);
  if (!res.ok) throw unauthorized(`Could not reach ${provider} to verify sign-in`);
  const { keys } = await res.json();
  keyCache.set(provider, { keys, fetchedAt: Date.now() });
  return keys;
}

function b64urlJson(part) {
  return JSON.parse(Buffer.from(part, 'base64url').toString('utf8'));
}

async function verifyJwtWithJwks(provider, token, audiences) {
  const parts = token.split('.');
  if (parts.length !== 3) throw unauthorized('Malformed identity token');
  const header = b64urlJson(parts[0]);
  const payload = b64urlJson(parts[1]);
  if (header.alg !== 'RS256') throw unauthorized('Unsupported token algorithm');

  let keys = await getKeys(provider);
  let jwk = keys.find((k) => k.kid === header.kid);
  if (!jwk) { keys = await getKeys(provider, { forceRefresh: true }); jwk = keys.find((k) => k.kid === header.kid); }
  if (!jwk) throw unauthorized('Unknown signing key');

  const publicKey = crypto.createPublicKey({ key: jwk, format: 'jwk' });
  const ok = crypto.verify('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`), publicKey, Buffer.from(parts[2], 'base64url'));
  if (!ok) throw unauthorized('Invalid identity token signature');

  const now = Math.floor(Date.now() / 1000);
  if (!PROVIDERS[provider].issuers.includes(payload.iss)) throw unauthorized('Wrong token issuer');
  if (!audiences.includes(payload.aud)) throw unauthorized('Token was issued for a different app');
  if (payload.exp < now) throw unauthorized('Identity token expired');
  return payload;
}

/** Returns { subject, email, emailVerified, name? }. */
async function verifyIdentityToken(provider, identityToken) {
  if (config.social.allowDemo && identityToken.startsWith('demo:')) {
    const email = identityToken.slice(5).trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw unauthorized('Demo token must be demo:<email>');
    return { subject: `demo-${provider.toLowerCase()}-${email}`, email, emailVerified: true, isDemo: true };
  }

  if (provider === 'APPLE') {
    if (!config.social.appleBundleId) throw unauthorized('Sign in with Apple is not configured on the server');
    const p = await verifyJwtWithJwks('APPLE', identityToken, [config.social.appleBundleId]);
    return { subject: p.sub, email: p.email, emailVerified: p.email_verified === true || p.email_verified === 'true' };
  }
  if (provider === 'GOOGLE') {
    if (!config.social.googleClientIds.length) throw unauthorized('Google Sign-In is not configured on the server');
    const p = await verifyJwtWithJwks('GOOGLE', identityToken, config.social.googleClientIds);
    return { subject: p.sub, email: p.email, emailVerified: Boolean(p.email_verified), name: p.name };
  }
  throw unauthorized('Unknown provider');
}

module.exports = { verifyIdentityToken };
