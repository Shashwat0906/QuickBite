'use strict';
const express = require('express');
const prisma = require('../lib/prisma');
const { validate, z, uuid } = require('../lib/validate');
const { asyncHandler, notFound } = require('../lib/errors');
const { requireAuth } = require('../middleware/auth');
const S = require('../serializers');

const router = express.Router();
router.use(requireAuth);

const body = z.object({
  label: z.string().trim().min(1).max(30),
  line1: z.string().trim().min(3, 'Enter the house / street').max(120),
  line2: z.string().trim().max(120).nullable().optional(),
  city: z.string().trim().min(2).max(60),
  pincode: z.string().trim().regex(/^[1-9][0-9]{5}$/, 'Enter a valid 6-digit PIN code'),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  isDefault: z.boolean().optional(),
});

async function owned(userId, id) {
  const a = await prisma.address.findFirst({ where: { id, userId } });
  if (!a) throw notFound('Address');
  return a;
}

router.get('/', asyncHandler(async (req, res) => {
  const list = await prisma.address.findMany({ where: { userId: req.user.id }, orderBy: [{ isDefault: 'desc' }, { createdAt: 'desc' }] });
  res.json({ addresses: list.map(S.address) });
}));

router.post('/', validate({ body }), asyncHandler(async (req, res) => {
  const count = await prisma.address.count({ where: { userId: req.user.id } });
  const isDefault = req.body.isDefault || count === 0;
  const created = await prisma.$transaction(async (tx) => {
    if (isDefault) await tx.address.updateMany({ where: { userId: req.user.id }, data: { isDefault: false } });
    return tx.address.create({ data: { ...req.body, isDefault, userId: req.user.id } });
  });
  res.status(201).json({ address: S.address(created) });
}));

router.put('/:id', validate({ params: z.object({ id: uuid }), body }), asyncHandler(async (req, res) => {
  await owned(req.user.id, req.params.id);
  const updated = await prisma.$transaction(async (tx) => {
    if (req.body.isDefault) await tx.address.updateMany({ where: { userId: req.user.id }, data: { isDefault: false } });
    return tx.address.update({ where: { id: req.params.id }, data: req.body });
  });
  res.json({ address: S.address(updated) });
}));

router.delete('/:id', validate({ params: z.object({ id: uuid }) }), asyncHandler(async (req, res) => {
  const a = await owned(req.user.id, req.params.id);
  await prisma.address.delete({ where: { id: a.id } });
  if (a.isDefault) {
    const next = await prisma.address.findFirst({ where: { userId: req.user.id }, orderBy: { createdAt: 'desc' } });
    if (next) await prisma.address.update({ where: { id: next.id }, data: { isDefault: true } });
  }
  res.status(204).end();
}));

module.exports = router;
