'use strict';
/** Shapes database rows into the stable JSON contract the iOS app decodes. */

const { LABELS } = require('./domain/orderStatus');

const user = (u) => ({
  id: u.id,
  name: u.name,
  email: u.email,
  phone: u.phone,
  authProvider: u.authProvider,
  notifyOrderUpdates: u.notifyOrderUpdates,
  notifyPromotions: u.notifyPromotions,
  createdAt: u.createdAt,
});

const address = (a) => ({
  id: a.id, label: a.label, line1: a.line1, line2: a.line2, city: a.city, pincode: a.pincode,
  latitude: a.latitude, longitude: a.longitude, isDefault: a.isDefault,
});

function isOpenNow(cafe, now = new Date()) {
  if (!cafe.isOpen) return false;
  // Times are IST; compute IST minutes-of-day regardless of server timezone.
  const ist = new Date(now.getTime() + (5.5 * 60 + now.getTimezoneOffset()) * 60000);
  const mins = ist.getHours() * 60 + ist.getMinutes();
  const toMins = (hhmm) => { const [h, m] = hhmm.split(':').map(Number); return h * 60 + m; };
  const open = toMins(cafe.opensAt);
  const close = toMins(cafe.closesAt);
  return close > open ? mins >= open && mins < close : mins >= open || mins < close;
}

const cafeSummary = (c, extra = {}) => ({
  id: c.id,
  name: c.name,
  slug: c.slug,
  description: c.description,
  imageUrl: c.imageUrl,
  bannerUrl: c.bannerUrl,
  cuisines: c.cuisines,
  rating: Math.round(c.rating * 10) / 10,
  ratingCount: c.ratingCount,
  deliveryFeePaise: c.deliveryFeePaise,
  minOrderPaise: c.minOrderPaise,
  isOpenNow: isOpenNow(c),
  opensAt: c.opensAt,
  closesAt: c.closesAt,
  isFeatured: c.isFeatured,
  latitude: c.latitude,
  longitude: c.longitude,
  addressLine: c.addressLine,
  phone: c.phone,
  ...extra,
});

const menuItem = (m) => ({
  id: m.id,
  cafeId: m.cafeId,
  categoryId: m.categoryId,
  name: m.name,
  description: m.description,
  imageUrl: m.imageUrl,
  pricePaise: m.pricePaise,
  diet: m.diet,
  isAvailable: m.isAvailable && (m.stock == null || m.stock > 0),
  isBestseller: m.isBestseller,
  popularity: m.popularity,
  ...(m.cafe ? { cafeName: m.cafe.name } : {}),
  customizations: (m.customizations || [])
    .sort((a, b) => a.sortOrder - b.sortOrder)
    .map((g) => ({
      id: g.id, name: g.name, minSelect: g.minSelect, maxSelect: g.maxSelect,
      options: g.options.map((o) => ({ id: o.id, name: o.name, extraPricePaise: o.extraPricePaise, isAvailable: o.isAvailable })),
    })),
});

const orderSummary = (o) => ({
  id: o.id,
  orderNumber: o.orderNumber,
  status: o.status,
  statusLabel: LABELS[o.status],
  cafe: o.cafe ? { id: o.cafe.id, name: o.cafe.name, imageUrl: o.cafe.imageUrl } : undefined,
  totalPaise: o.totalPaise,
  itemCount: o.items ? o.items.reduce((s, i) => s + i.quantity, 0) : undefined,
  itemsPreview: o.items ? o.items.map((i) => `${i.quantity} × ${i.name}`).join(', ') : undefined,
  createdAt: o.createdAt,
  estimatedMinutes: o.estimatedMinutes,
  isReviewed: o.review != null,
});

const payment = (p) => ({
  id: p.id, provider: p.provider, status: p.status, amountPaise: p.amountPaise,
  providerOrderId: p.providerOrderId, failureReason: p.failureReason, createdAt: p.createdAt,
});

const orderDetail = (o) => ({
  ...orderSummary(o),
  cafe: o.cafe ? { id: o.cafe.id, name: o.cafe.name, imageUrl: o.cafe.imageUrl, phone: o.cafe.phone, latitude: o.cafe.latitude, longitude: o.cafe.longitude, addressLine: o.cafe.addressLine } : undefined,
  items: o.items.map((i) => ({ id: i.id, menuItemId: i.menuItemId, name: i.name, quantity: i.quantity, unitPricePaise: i.unitPricePaise, lineTotalPaise: i.lineTotalPaise, options: i.options })),
  bill: { subtotalPaise: o.subtotalPaise, deliveryFeePaise: o.deliveryFeePaise, taxPaise: o.taxPaise, discountPaise: o.discountPaise, totalPaise: o.totalPaise },
  couponCode: o.coupon ? o.coupon.code : null,
  deliveryAddress: o.deliveryAddress,
  timeline: (o.events || []).sort((a, b) => a.createdAt - b.createdAt).map((e) => ({ status: e.status, label: LABELS[e.status], note: e.note, at: e.createdAt })),
  payments: (o.payments || []).map(payment),
  isDemoTracking: o.isDemoTracking,
  cancelReason: o.cancelReason,
  deliveredAt: o.deliveredAt,
  canCancel: ['PENDING_PAYMENT', 'PLACED', 'CONFIRMED'].includes(o.status),
  paymentMethod: o.paymentMethod,
  canReview: o.status === 'DELIVERED' && o.review == null,
});

const review = (r) => ({
  id: r.id, orderId: r.orderId, cafeId: r.cafeId, rating: r.rating, comment: r.comment, createdAt: r.createdAt,
  userName: r.user ? r.user.name.split(' ')[0] : undefined,
  cafeName: r.cafe ? r.cafe.name : undefined,
});

const notification = (n) => ({ id: n.id, title: n.title, body: n.body, orderId: n.orderId, isRead: n.isRead, createdAt: n.createdAt });

module.exports = { user, address, cafeSummary, menuItem, orderSummary, orderDetail, payment, review, notification, isOpenNow };
