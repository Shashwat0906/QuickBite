'use strict';
const { Prisma } = require('@prisma/client');
const { AppError } = require('../lib/errors');

function notFoundHandler(req, _res, next) {
  next(new AppError(404, 'ROUTE_NOT_FOUND', `No route for ${req.method} ${req.path}`));
}

function errorHandler(err, req, res, _next) {
  let status = err.status || 500;
  let code = err.code || 'INTERNAL_ERROR';
  let message = err.message || 'Something went wrong';
  let details = err.details;

  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    if (err.code === 'P2002') {
      status = 409; code = 'DUPLICATE'; message = 'That already exists';
    } else if (err.code === 'P2025') {
      status = 404; code = 'NOT_FOUND'; message = 'Resource not found';
    } else {
      status = 500; code = 'DATABASE_ERROR';
    }
  } else if (err.type === 'entity.parse.failed') {
    status = 400; code = 'INVALID_JSON'; message = 'Request body is not valid JSON';
  } else if (!(err instanceof AppError) && !err.status) {
    status = 500;
  }

  if (status >= 500) {
    console.error(`[${req.method} ${req.originalUrl}]`, err);
    if (process.env.NODE_ENV === 'production') { message = 'Something went wrong on our side'; details = undefined; }
  }
  res.status(status).json({ error: { code, message, ...(details ? { details } : {}) } });
}

module.exports = { notFoundHandler, errorHandler };
