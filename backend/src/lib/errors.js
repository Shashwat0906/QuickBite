'use strict';
/**
 * Every error the API returns has the same JSON shape:
 *   { "error": { "code": "VALIDATION_ERROR", "message": "...", "details": [...] } }
 * The iOS NetworkKit decodes this into `APIError.server(code:message:)`.
 */
class AppError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

const badRequest = (msg, details) => new AppError(400, 'BAD_REQUEST', msg, details);
const unauthorized = (msg = 'Please sign in again') => new AppError(401, 'UNAUTHORIZED', msg);
const forbidden = (msg = 'You are not allowed to do that') => new AppError(403, 'FORBIDDEN', msg);
const notFound = (what = 'Resource') => new AppError(404, 'NOT_FOUND', `${what} not found`);
const conflict = (msg, code = 'CONFLICT') => new AppError(409, code, msg);
const unprocessable = (msg, code = 'UNPROCESSABLE') => new AppError(422, code, msg);

/** Wraps async route handlers so rejected promises reach the error middleware. */
const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

module.exports = { AppError, badRequest, unauthorized, forbidden, notFound, conflict, unprocessable, asyncHandler };
