'use strict';
const { PrismaClient } = require('@prisma/client');

// One client per process; Prisma manages its own connection pool.
const prisma = new PrismaClient({
  log: process.env.NODE_ENV === 'development' ? ['warn', 'error'] : ['error'],
});

module.exports = prisma;
