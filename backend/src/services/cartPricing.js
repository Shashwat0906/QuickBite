'use strict';
const prisma = require('../lib/prisma');
const P = require('../domain/pricing');
const S = require('../serializers');

const MAX_QTY_PER_LINE = 20;

/**
 * Prices a cart from *database* prices and reports every problem that would
 * block checkout. Used by GET /cart, POST /cart/validate and order creation, so
 * all three always agree.
 *
 * input = { items: [{ id?, menuItemId, quantity, optionIds }], couponCode? }
 */
async function priceCart(userId, input) {
  const items = input.items || [];
  const issues = [];
  if (items.length === 0) {
    return { cafe: null, lines: [], bill: null, coupon: null, issues: [{ code: 'EMPTY_CART', message: 'Your cart is empty' }], canCheckout: false };
  }

  const menuItems = await prisma.menuItem.findMany({
    where: { id: { in: [...new Set(items.map((i) => i.menuItemId))] } },
    include: { customizations: { include: { options: true } }, cafe: true },
  });
  const byId = new Map(menuItems.map((m) => [m.id, m]));

  const cafeIds = new Set(menuItems.map((m) => m.cafeId));
  if (cafeIds.size > 1) issues.push({ code: 'MULTIPLE_CAFES', message: 'You can only order from one cafe at a time' });
  const cafe = menuItems[0]?.cafe || null;
  if (cafe && !S.isOpenNow(cafe)) issues.push({ code: 'CAFE_CLOSED', message: `${cafe.name} is closed right now` });

  const lines = [];
  for (const it of items) {
    const m = byId.get(it.menuItemId);
    if (!m) {
      issues.push({ code: 'ITEM_REMOVED', message: 'An item in your cart is no longer on the menu', menuItemId: it.menuItemId });
      continue;
    }
    let issue = null;
    const sel = P.validateSelection(m.customizations, it.optionIds || []);
    if (!m.isAvailable) issue = { code: 'ITEM_UNAVAILABLE', message: `${m.name} is currently unavailable` };
    else if (m.stock != null && m.stock < it.quantity) issue = { code: 'OUT_OF_STOCK', message: m.stock === 0 ? `${m.name} is sold out` : `Only ${m.stock} ${m.name} left` };
    else if (!sel.ok) issue = { code: 'INVALID_OPTIONS', message: `${m.name}: ${sel.reason}` };
    else if (it.quantity < 1 || it.quantity > MAX_QTY_PER_LINE) issue = { code: 'INVALID_QUANTITY', message: `Quantity must be between 1 and ${MAX_QTY_PER_LINE}` };
    if (issue) issues.push({ ...issue, menuItemId: m.id, lineId: it.id });

    const options = sel.ok ? sel.options.map((o) => ({ id: o.id, name: o.name, extraPricePaise: o.extraPricePaise })) : [];
    const unitPricePaise = P.unitPrice(m.pricePaise, options);
    lines.push({
      id: it.id,
      menuItem: S.menuItem(m),
      quantity: it.quantity,
      optionIds: options.map((o) => o.id),
      options,
      unitPricePaise,
      lineTotalPaise: unitPricePaise * it.quantity,
      issue,
    });
  }

  if (!cafe) {
    return { cafe: null, lines, bill: null, coupon: null, issues, canCheckout: false };
  }

  const pricedLines = lines.filter((l) => !l.issue);
  let coupon = null;
  let discountPaise = 0;
  const preBill = P.computeBill({ lines: pricedLines, cafe });
  if (input.couponCode) {
    const row = await prisma.coupon.findUnique({ where: { code: input.couponCode.toUpperCase() } });
    const timesUsedByUser = row && userId
      ? await prisma.order.count({ where: { userId, couponId: row.id, status: { not: 'CANCELLED' } } })
      : 0;
    const result = P.couponDiscount(row, preBill.subtotalPaise, { timesUsedByUser });
    coupon = { code: input.couponCode.toUpperCase(), isValid: result.ok, message: result.ok ? row.description : result.reason, discountPaise: result.ok ? result.discountPaise : 0, couponId: row?.id };
    if (result.ok) discountPaise = result.discountPaise;
  }

  const bill = P.computeBill({ lines: pricedLines, cafe, discountPaise });
  return {
    cafe: S.cafeSummary(cafe),
    lines,
    bill,
    coupon,
    issues,
    canCheckout: issues.length === 0 && pricedLines.length > 0,
  };
}

/** Strip internal fields before sending to clients. */
function publicCart(priced) {
  const { coupon, ...rest } = priced;
  return { ...rest, coupon: coupon ? { code: coupon.code, isValid: coupon.isValid, message: coupon.message, discountPaise: coupon.discountPaise } : null };
}

module.exports = { priceCart, publicCart, MAX_QTY_PER_LINE };
