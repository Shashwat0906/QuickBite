'use strict';
/**
 * Pricing engine — the single source of truth for every amount the user pays.
 *
 * The iOS app shows an *estimate* using the same formula, but the server always
 * recomputes from database prices before creating an order or payment. Nothing
 * price-related sent by the client is trusted.
 *
 * Pure functions only (no database, no I/O) so the rules are easy to unit test.
 */

const TAX_RATE_BPS = 500; // 5% GST on restaurant food, in basis points
const FREE_DELIVERY_THRESHOLD_PAISE = 49900; // free delivery from ₹499
const SMALL_ORDER_FEE_PAISE = 1500; // added below the cafe's minimum order value

/** Unit price of one line = item base price + every selected option's extra. */
function unitPrice(basePricePaise, options = []) {
  return options.reduce((sum, o) => sum + o.extraPricePaise, basePricePaise);
}

/**
 * Validate that the chosen options are legal for the item's customization groups.
 * Returns { ok: true, options } or { ok: false, reason }.
 */
function validateSelection(groups, optionIds) {
  const chosen = new Set(optionIds);
  const allOptions = new Map();
  for (const g of groups) for (const o of g.options) allOptions.set(o.id, { ...o, groupId: g.id });

  for (const id of chosen) {
    if (!allOptions.has(id)) return { ok: false, reason: 'Unknown customization option' };
    if (!allOptions.get(id).isAvailable) return { ok: false, reason: `${allOptions.get(id).name} is unavailable` };
  }
  for (const g of groups) {
    const count = g.options.filter((o) => chosen.has(o.id)).length;
    if (count < g.minSelect) return { ok: false, reason: `Please choose ${g.name}` };
    if (count > g.maxSelect) return { ok: false, reason: `Choose at most ${g.maxSelect} for ${g.name}` };
  }
  return { ok: true, options: [...chosen].map((id) => allOptions.get(id)) };
}

/**
 * Coupon discount for a given subtotal. Pure: usage counts are passed in.
 * Returns { ok: true, discountPaise } or { ok: false, reason }.
 */
function couponDiscount(coupon, subtotalPaise, { now = new Date(), timesUsedByUser = 0 } = {}) {
  if (!coupon || !coupon.isActive) return { ok: false, reason: 'This coupon is not valid' };
  if (coupon.validFrom && now < new Date(coupon.validFrom)) return { ok: false, reason: 'This coupon is not active yet' };
  if (coupon.validUntil && now > new Date(coupon.validUntil)) return { ok: false, reason: 'This coupon has expired' };
  if (timesUsedByUser >= coupon.usageLimitPerUser) return { ok: false, reason: 'You have already used this coupon' };
  if (subtotalPaise < coupon.minOrderPaise) {
    return { ok: false, reason: `Add items worth ₹${((coupon.minOrderPaise - subtotalPaise) / 100).toFixed(0)} more to use this coupon` };
  }
  let discount = coupon.type === 'FLAT' ? coupon.value : Math.floor((subtotalPaise * coupon.value) / 100);
  if (coupon.maxDiscountPaise != null) discount = Math.min(discount, coupon.maxDiscountPaise);
  discount = Math.min(discount, subtotalPaise); // never negative totals
  return { ok: true, discountPaise: discount };
}

/**
 * Full bill. `lines` = [{ unitPricePaise, quantity }].
 * Tax is charged on the discounted food value (how Indian delivery apps bill GST).
 */
function computeBill({ lines, cafe, discountPaise = 0 }) {
  const subtotalPaise = lines.reduce((s, l) => s + l.unitPricePaise * l.quantity, 0);
  const discount = Math.min(discountPaise, subtotalPaise);
  let deliveryFeePaise = subtotalPaise >= FREE_DELIVERY_THRESHOLD_PAISE ? 0 : cafe.deliveryFeePaise;
  if (subtotalPaise > 0 && subtotalPaise < cafe.minOrderPaise) deliveryFeePaise += SMALL_ORDER_FEE_PAISE;
  const taxPaise = Math.round(((subtotalPaise - discount) * TAX_RATE_BPS) / 10000);
  const totalPaise = subtotalPaise - discount + deliveryFeePaise + taxPaise;
  return { subtotalPaise, discountPaise: discount, deliveryFeePaise, taxPaise, totalPaise };
}

/** Line key so "Latte (Large, Oat milk)" twice becomes one line with quantity 2. */
function lineKey(menuItemId, optionIds = []) {
  return `${menuItemId}|${[...optionIds].sort().join(',')}`;
}

/** Delivery estimate: prep time + ~2 min per km at city speeds + 2 min handover. */
function estimateMinutes(cafe, distanceKm) {
  return Math.max(10, Math.round(cafe.avgPrepMinutes + distanceKm * 2 + 2));
}

/** Haversine distance in km. */
function distanceKm(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

module.exports = {
  TAX_RATE_BPS,
  FREE_DELIVERY_THRESHOLD_PAISE,
  SMALL_ORDER_FEE_PAISE,
  unitPrice,
  validateSelection,
  couponDiscount,
  computeBill,
  lineKey,
  estimateMinutes,
  distanceKm,
};
