'use strict';
const { test, describe, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startServer, newUser, prisma } = require('./helpers');

let s;
before(async () => { s = await startServer(); });
after(async () => { await s.stop(); await prisma.$disconnect(); });

describe('auth API', () => {
  test('health check reports database ok', async () => {
    const r = await s.api('GET', '/health');
    assert.equal(r.status, 200);
    assert.equal(r.body.database, 'ok');
  });

  test('register → me → update profile', async () => {
    const { token, user } = await newUser(s.api);
    assert.ok(user.id);
    const me = await s.api('GET', '/api/v1/auth/me', { token });
    assert.equal(me.status, 200);
    assert.equal(me.body.user.email, user.email);

    const upd = await s.api('PATCH', '/api/v1/auth/me', { token, body: { name: 'Renamed', phone: '+919876543210' } });
    assert.equal(upd.status, 200);
    assert.equal(upd.body.user.name, 'Renamed');
  });

  test('validation errors are descriptive', async () => {
    const r = await s.api('POST', '/api/v1/auth/register', { body: { name: 'A', email: 'nope', password: 'short' } });
    assert.equal(r.status, 400);
    assert.equal(r.body.error.code, 'VALIDATION_ERROR');
    assert.ok(r.body.error.details.length >= 2);
  });

  test('duplicate email is rejected with 409', async () => {
    const { email } = await newUser(s.api);
    const r = await s.api('POST', '/api/v1/auth/register', { body: { name: 'Again', email, password: 'Passw0rd!' } });
    assert.equal(r.status, 409);
    assert.equal(r.body.error.code, 'EMAIL_TAKEN');
  });

  test('login with wrong password → 401, correct → tokens', async () => {
    const { email } = await newUser(s.api);
    const bad = await s.api('POST', '/api/v1/auth/login', { body: { email, password: 'WrongPass1' } });
    assert.equal(bad.status, 401);
    const ok = await s.api('POST', '/api/v1/auth/login', { body: { email, password: 'Passw0rd!' } });
    assert.equal(ok.status, 200);
    assert.ok(ok.body.tokens.accessToken);
  });

  test('refresh rotates the token and reuse is rejected', async () => {
    const { refreshToken } = await newUser(s.api);
    const first = await s.api('POST', '/api/v1/auth/refresh', { body: { refreshToken } });
    assert.equal(first.status, 200);
    assert.notEqual(first.body.tokens.refreshToken, refreshToken);
    const reuse = await s.api('POST', '/api/v1/auth/refresh', { body: { refreshToken } });
    assert.equal(reuse.status, 401);
    // Reuse revokes the whole family, including the new token.
    const after = await s.api('POST', '/api/v1/auth/refresh', { body: { refreshToken: first.body.tokens.refreshToken } });
    assert.equal(after.status, 401);
  });

  test('logout revokes the refresh token', async () => {
    const { refreshToken } = await newUser(s.api);
    assert.equal((await s.api('POST', '/api/v1/auth/logout', { body: { refreshToken } })).status, 204);
    assert.equal((await s.api('POST', '/api/v1/auth/refresh', { body: { refreshToken } })).status, 401);
  });

  test('protected routes need a token', async () => {
    const r = await s.api('GET', '/api/v1/auth/me');
    assert.equal(r.status, 401);
  });

  test('demo social sign-in creates then reuses the account', async () => {
    const email = `apple-${Date.now()}@test.dev`;
    const a = await s.api('POST', '/api/v1/auth/social', { body: { provider: 'APPLE', identityToken: `demo:${email}`, name: 'Apple Person' } });
    assert.equal(a.status, 200);
    assert.equal(a.body.isDemo, true);
    const b = await s.api('POST', '/api/v1/auth/social', { body: { provider: 'APPLE', identityToken: `demo:${email}` } });
    assert.equal(b.body.user.id, a.body.user.id);
    assert.equal(b.body.user.name, 'Apple Person');
  });

  test('account deletion anonymises and blocks login', async () => {
    const { token, email } = await newUser(s.api);
    assert.equal((await s.api('DELETE', '/api/v1/auth/me', { token })).status, 204);
    const login = await s.api('POST', '/api/v1/auth/login', { body: { email, password: 'Passw0rd!' } });
    assert.equal(login.status, 401);
  });
});
