'use strict';
const express = require('express');
const prisma = require('../lib/prisma');
const { validate, z, uuid, pagination, paginate, pageMeta } = require('../lib/validate');
const { asyncHandler, notFound } = require('../lib/errors');
const { distanceKm, estimateMinutes } = require('../domain/pricing');
const S = require('../serializers');

const router = express.Router();

// Default location (Connaught Place, New Delhi) used when the app has no location yet.
const DEFAULT_LAT = 28.6315;
const DEFAULT_LNG = 77.2167;
const MAX_RADIUS_KM = 15;

const itemInclude = { customizations: { include: { options: true } } };

const coords = z.object({
  lat: z.coerce.number().min(-90).max(90).default(DEFAULT_LAT),
  lng: z.coerce.number().min(-180).max(180).default(DEFAULT_LNG),
});

function withDistance(cafe, lat, lng) {
  const km = distanceKm(lat, lng, cafe.latitude, cafe.longitude);
  return S.cafeSummary(cafe, { distanceKm: Math.round(km * 10) / 10, deliveryMinutes: estimateMinutes(cafe, km) });
}

/**
 * GET /home — everything the Home tab needs in one round trip:
 * offers, featured cafes, categories, popular & bestseller dishes.
 */
router.get('/home', validate({ query: coords }), asyncHandler(async (req, res) => {
  const { lat, lng } = req.query;
  const [cafes, popular, bestsellers, coupons] = await Promise.all([
    prisma.cafe.findMany(),
    prisma.menuItem.findMany({ where: { isAvailable: true }, orderBy: { popularity: 'desc' }, take: 10, include: { ...itemInclude, cafe: true } }),
    prisma.menuItem.findMany({ where: { isAvailable: true, isBestseller: true }, orderBy: { popularity: 'desc' }, take: 10, include: { ...itemInclude, cafe: true } }),
    prisma.coupon.findMany({ where: { isActive: true, OR: [{ validUntil: null }, { validUntil: { gt: new Date() } }] }, orderBy: { minOrderPaise: 'asc' } }),
  ]);
  const nearby = cafes
    .map((c) => withDistance(c, lat, lng))
    .filter((c) => c.distanceKm <= MAX_RADIUS_KM)
    .sort((a, b) => a.distanceKm - b.distanceKm);
  const categoryRows = await prisma.menuCategory.groupBy({ by: ['name'], _count: { name: true }, orderBy: { _count: { name: 'desc' } }, take: 8 });

  res.json({
    offers: coupons.map((c) => ({ code: c.code, description: c.description, type: c.type, value: c.value, minOrderPaise: c.minOrderPaise, maxDiscountPaise: c.maxDiscountPaise })),
    featuredCafes: nearby.filter((c) => c.isFeatured),
    nearbyCafes: nearby,
    categories: categoryRows.map((r) => r.name),
    popularDishes: popular.map(S.menuItem),
    bestsellers: bestsellers.map(S.menuItem),
    fastestDeliveryMinutes: nearby.length ? Math.min(...nearby.map((c) => c.deliveryMinutes)) : null,
  });
}));

/** GET /cafes — nearby cafes with filters. */
router.get(
  '/cafes',
  validate({
    query: coords.merge(pagination).extend({
      category: z.string().trim().max(40).optional(),
      minRating: z.coerce.number().min(0).max(5).optional(),
      openNow: z.enum(['true', 'false']).optional(),
      featured: z.enum(['true', 'false']).optional(),
      sort: z.enum(['distance', 'rating', 'deliveryTime']).default('distance'),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { lat, lng, category, minRating, openNow, featured, sort } = req.query;
    const where = {
      ...(minRating ? { rating: { gte: minRating } } : {}),
      ...(featured === 'true' ? { isFeatured: true } : {}),
      ...(category ? { categories: { some: { name: { equals: category, mode: 'insensitive' } } } } : {}),
    };
    let list = (await prisma.cafe.findMany({ where }))
      .map((c) => withDistance(c, lat, lng))
      .filter((c) => c.distanceKm <= MAX_RADIUS_KM);
    if (openNow === 'true') list = list.filter((c) => c.isOpenNow);
    const sorters = { distance: (a, b) => a.distanceKm - b.distanceKm, rating: (a, b) => b.rating - a.rating, deliveryTime: (a, b) => a.deliveryMinutes - b.deliveryMinutes };
    list.sort(sorters[sort]);
    const { skip, take } = paginate(req.query);
    res.json({ cafes: list.slice(skip, skip + take), meta: pageMeta(req.query, list.length) });
  }),
);

/** GET /cafes/:id — cafe + full menu grouped by category. */
router.get('/cafes/:id', validate({ params: z.object({ id: uuid }), query: coords }), asyncHandler(async (req, res) => {
  const cafe = await prisma.cafe.findUnique({
    where: { id: req.params.id },
    include: { categories: { orderBy: { sortOrder: 'asc' }, include: { items: { include: itemInclude, orderBy: [{ isBestseller: 'desc' }, { name: 'asc' }] } } } },
  });
  if (!cafe) throw notFound('Cafe');
  res.json({
    cafe: withDistance(cafe, req.query.lat, req.query.lng),
    menu: cafe.categories.map((cat) => ({ id: cat.id, name: cat.name, items: cat.items.map(S.menuItem) })),
  });
}));

router.get('/cafes/:id/categories', validate({ params: z.object({ id: uuid }) }), asyncHandler(async (req, res) => {
  const categories = await prisma.menuCategory.findMany({ where: { cafeId: req.params.id }, orderBy: { sortOrder: 'asc' }, include: { _count: { select: { items: true } } } });
  res.json({ categories: categories.map((c) => ({ id: c.id, name: c.name, itemCount: c._count.items })) });
}));

router.get(
  '/cafes/:id/items',
  validate({ params: z.object({ id: uuid }), query: pagination.extend({ categoryId: uuid.optional(), veg: z.enum(['true', 'false']).optional() }) }),
  asyncHandler(async (req, res) => {
    const where = { cafeId: req.params.id, ...(req.query.categoryId ? { categoryId: req.query.categoryId } : {}), ...(req.query.veg === 'true' ? { diet: 'VEG' } : {}) };
    const [items, total] = await Promise.all([
      prisma.menuItem.findMany({ where, include: itemInclude, orderBy: { name: 'asc' }, ...paginate(req.query) }),
      prisma.menuItem.count({ where }),
    ]);
    res.json({ items: items.map(S.menuItem), meta: pageMeta(req.query, total) });
  }),
);

router.get('/items/:id', validate({ params: z.object({ id: uuid }) }), asyncHandler(async (req, res) => {
  const item = await prisma.menuItem.findUnique({ where: { id: req.params.id }, include: { ...itemInclude, cafe: true } });
  if (!item) throw notFound('Menu item');
  res.json({ item: S.menuItem(item) });
}));

/**
 * GET /search?q=latte — cafes and dishes. Matches names, descriptions,
 * cuisines and category names (case-insensitive).
 */
router.get(
  '/search',
  validate({
    query: coords.merge(pagination).extend({
      q: z.string().trim().max(60).default(''),
      category: z.string().trim().max(40).optional(),
      veg: z.enum(['true', 'false']).optional(),
      maxPrice: z.coerce.number().int().positive().optional(),
      minRating: z.coerce.number().min(0).max(5).optional(),
      availableOnly: z.enum(['true', 'false']).optional(),
      sort: z.enum(['relevance', 'popularity', 'priceLow', 'priceHigh', 'rating']).default('relevance'),
    }),
  }),
  asyncHandler(async (req, res) => {
    const { q, category, veg, maxPrice, minRating, availableOnly, sort, lat, lng } = req.query;
    const text = q ? { contains: q, mode: 'insensitive' } : undefined;

    const itemWhere = {
      ...(text ? { OR: [{ name: text }, { description: text }, { category: { name: text } }, { cafe: { name: text } }] } : {}),
      ...(category ? { category: { name: { equals: category, mode: 'insensitive' } } } : {}),
      ...(veg === 'true' ? { diet: 'VEG' } : {}),
      ...(maxPrice ? { pricePaise: { lte: maxPrice } } : {}),
      ...(minRating ? { cafe: { rating: { gte: minRating } } } : {}),
      ...(availableOnly === 'true' ? { isAvailable: true } : {}),
    };
    const orderBy = {
      relevance: [{ isBestseller: 'desc' }, { popularity: 'desc' }],
      popularity: [{ popularity: 'desc' }],
      priceLow: [{ pricePaise: 'asc' }],
      priceHigh: [{ pricePaise: 'desc' }],
      rating: [{ cafe: { rating: 'desc' } }],
    }[sort];

    const [items, total, cafes] = await Promise.all([
      prisma.menuItem.findMany({ where: itemWhere, include: { ...itemInclude, cafe: true }, orderBy, ...paginate(req.query) }),
      prisma.menuItem.count({ where: itemWhere }),
      text && req.query.page === 1
        ? prisma.cafe.findMany({ where: { OR: [{ name: text }, { description: text }, { cuisines: { has: q.toLowerCase() } }] }, take: 10 })
        : Promise.resolve([]),
    ]);

    res.json({
      query: q,
      cafes: cafes.map((c) => withDistance(c, lat, lng)),
      items: items.map(S.menuItem),
      meta: pageMeta(req.query, total),
    });
  }),
);

router.get('/search/suggestions', asyncHandler(async (_req, res) => {
  const [top, categories] = await Promise.all([
    prisma.menuItem.findMany({ orderBy: { popularity: 'desc' }, take: 6, select: { name: true } }),
    prisma.menuCategory.groupBy({ by: ['name'], _count: { name: true }, orderBy: { _count: { name: 'desc' } }, take: 8 }),
  ]);
  res.json({ suggestions: [...new Set(top.map((t) => t.name))], categories: categories.map((c) => c.name) });
}));

module.exports = router;
