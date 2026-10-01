'use strict';
const { z } = require('zod');
const { AppError } = require('./errors');

/**
 * validate({ body, query, params }) — Zod schemas per request part.
 * Parsed (and coerced) values replace the originals so handlers get clean data.
 */
function validate(schemas) {
  return (req, _res, next) => {
    for (const part of ['params', 'query', 'body']) {
      if (!schemas[part]) continue;
      const result = schemas[part].safeParse(req[part] ?? {});
      if (!result.success) {
        const details = result.error.issues.map((i) => ({ field: i.path.join('.') || part, message: i.message }));
        return next(new AppError(400, 'VALIDATION_ERROR', details[0]?.message || 'Invalid request', details));
      }
      if (part === 'query') {
        // req.query is a getter in Express 5; replace keys in place to stay compatible.
        Object.keys(req.query).forEach((k) => delete req.query[k]);
        Object.assign(req.query, result.data);
      } else {
        req[part] = result.data;
      }
    }
    next();
  };
}

const pagination = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});

const paginate = ({ page, limit }) => ({ skip: (page - 1) * limit, take: limit });
const pageMeta = ({ page, limit }, total) => ({ page, limit, total, totalPages: Math.ceil(total / limit), hasMore: page * limit < total });

const uuid = z.string().uuid();

module.exports = { validate, pagination, paginate, pageMeta, uuid, z };
