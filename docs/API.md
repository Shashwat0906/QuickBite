# QuickBite REST API

Base URL: `https://<your-service>.onrender.com/api/v1` (local: `http://localhost:4000/api/v1`).
All bodies are JSON. Money values are integers in **paise**. Timestamps are ISO-8601 UTC.

**Auth:** `Authorization: Bearer <accessToken>` on endpoints marked 🔒. Access tokens last 15
minutes; refresh with `POST /auth/refresh`.

**Errors** always look like:

```json
{ "error": { "code": "VALIDATION_ERROR", "message": "Enter a valid email address", "details": [{ "field": "email", "message": "…" }] } }
```

| Status | Meaning |
| --- | --- |
| 400 | Validation failed (`VALIDATION_ERROR`, `INVALID_JSON`) |
| 401 | Missing/expired token (`UNAUTHORIZED`, `TOKEN_EXPIRED`, `INVALID_CREDENTIALS`) |
| 403 | Authenticated but not allowed (`FORBIDDEN`) |
| 404 | Not found / not yours (`NOT_FOUND`) |
| 409 | Conflict (`EMAIL_TAKEN`, `CART_CAFE_CONFLICT`, `INVALID_STATUS_TRANSITION`, `NOT_CANCELLABLE`, `ALREADY_REVIEWED`) |
| 422 | Valid request that can't be processed (`CART_INVALID`, `COUPON_INVALID`, `ORDER_NOT_DELIVERED`, `PAYMENT_VERIFICATION_FAILED`) |
| 429 | Rate limited |

List endpoints accept `page` (default 1) and `limit` (default 20, max 50) and return
`meta: { page, limit, total, totalPages, hasMore }`.

## Health

| Method | Path | Description |
| --- | --- | --- |
| GET | `/health` *(outside /api/v1)* | `{ status, database, version, features: { razorpay, mockPayments, fcm, demoOrderProgression, socialLoginDemo } }` |

## Auth & profile

| Method | Path | Body | Notes |
| --- | --- | --- | --- |
| POST | `/auth/register` | `{ name, email, password, phone? }` | Password ≥ 8 chars with a letter and a number. → `201 { user, tokens }` |
| POST | `/auth/login` | `{ email, password }` | → `{ user, tokens }` |
| POST | `/auth/social` | `{ provider: "APPLE"\|"GOOGLE", identityToken, name? }` | Verifies the provider JWT against Apple/Google JWKS. With `SOCIAL_LOGIN_DEMO=true`, `identityToken: "demo:<email>"` is accepted and the response has `isDemo: true`. |
| POST | `/auth/refresh` | `{ refreshToken }` | Rotates: returns new access + refresh token. Reusing an old refresh token revokes all sessions. |
| POST | `/auth/logout` | `{ refreshToken?, deviceToken? }` | Revokes the session and detaches the push token. `204` |
| GET 🔒 | `/auth/me` | | `{ user }` |
| PATCH 🔒 | `/auth/me` | `{ name?, email?, phone?, notifyOrderUpdates?, notifyPromotions? }` | |
| DELETE 🔒 | `/auth/me` | | Deletes the account (anonymises user, removes addresses/devices/sessions). `204` |

`tokens = { accessToken, refreshToken, expiresAt }`

## Addresses 🔒

| Method | Path | Body |
| --- | --- | --- |
| GET | `/addresses` | → `{ addresses: [...] }` (default first) |
| POST | `/addresses` | `{ label, line1, line2?, city, pincode (6 digits), latitude, longitude, isDefault? }` — first address becomes default |
| PUT | `/addresses/:id` | same as POST |
| DELETE | `/addresses/:id` | `204` (another address becomes default if needed) |

## Catalogue & search

All accept `lat`, `lng` (defaults: Connaught Place, New Delhi). Cafés outside 15 km are excluded.

| Method | Path | Query | Returns |
| --- | --- | --- | --- |
| GET | `/home` | | `{ offers, featuredCafes, nearbyCafes, categories, popularDishes, bestsellers, fastestDeliveryMinutes }` |
| GET | `/cafes` | `category, minRating, openNow, featured, sort=distance\|rating\|deliveryTime, page, limit` | `{ cafes, meta }` |
| GET | `/cafes/:id` | | `{ cafe, menu: [{ id, name, items: [MenuItem] }] }` |
| GET | `/cafes/:id/categories` | | `{ categories: [{ id, name, itemCount }] }` |
| GET | `/cafes/:id/items` | `categoryId, veg, page, limit` | `{ items, meta }` |
| GET | `/items/:id` | | `{ item }` |
| GET | `/search` | `q, category, veg, maxPrice (paise), minRating, availableOnly, sort=relevance\|popularity\|priceLow\|priceHigh\|rating, page, limit` | `{ query, cafes, items, meta }` |
| GET | `/search/suggestions` | | `{ suggestions, categories }` |
| GET | `/cafes/:id/reviews` | `page, limit` | `{ reviews, distribution: { "1": n, … "5": n }, meta }` |

`Cafe` includes `isOpenNow` (computed in IST), `distanceKm`, `deliveryMinutes` (prep time + distance).
`MenuItem` includes `diet` (`VEG`/`NON_VEG`/`EGG`), `isAvailable` (false when sold out) and
`customizations: [{ id, name, minSelect, maxSelect, options: [{ id, name, extraPricePaise, isAvailable }] }]`.

## Cart 🔒

Every cart response is `{ cart: PricedCart }`:

```json
{
  "cafe": { "...": "Cafe" },
  "lines": [{ "id": "…", "menuItem": { }, "quantity": 2, "optionIds": ["…"], "unitPricePaise": 22900, "lineTotalPaise": 45800, "issue": null }],
  "bill": { "subtotalPaise": 45800, "discountPaise": 10000, "deliveryFeePaise": 0, "taxPaise": 1790, "totalPaise": 37590 },
  "coupon": { "code": "WELCOME50", "isValid": true, "message": "50% off up to ₹100…", "discountPaise": 10000 },
  "issues": [{ "code": "OUT_OF_STOCK", "message": "Only 2 Tiramisu left", "menuItemId": "…" }],
  "canCheckout": true
}
```

| Method | Path | Body | Notes |
| --- | --- | --- | --- |
| GET | `/cart` | | |
| PUT | `/cart` | `{ items: [{ menuItemId, quantity, optionIds }], couponCode? }` | Replace (used by the app to sync its local cart). Identical lines are merged. |
| POST | `/cart/items` | `{ menuItemId, quantity, optionIds, replaceCart? }` | `409 CART_CAFE_CONFLICT` if the cart holds another café's items (retry with `replaceCart: true`). |
| PATCH | `/cart/items/:lineId` | `{ quantity?, optionIds? }` | quantity `0` removes |
| DELETE | `/cart/items/:lineId` | | |
| DELETE | `/cart` | | clear |
| PUT | `/cart/coupon` | `{ code \| null }` | |
| POST | `/cart/validate` | | Re-prices and lists every blocking issue |

Pricing (server-side, never trusted from the client): subtotal = Σ (base + option extras) × qty;
delivery fee waived from ₹499, ₹15 small-order fee below the café minimum; 5% GST on
(subtotal − discount); coupon rules: min order, cap, validity, per-user usage limit.

## Orders 🔒

| Method | Path | Body | Notes |
| --- | --- | --- | --- |
| POST | `/orders` | `{ addressId, paymentMethod: "RAZORPAY"\|"MOCK"\|"CASH_ON_DELIVERY", idempotencyKey }` | Creates the order from the server cart. `201 { order, payment, replayed:false }`; the same key again → `200 { …, replayed:true }`. Online payments start as `PENDING_PAYMENT`. |
| GET | `/orders` | `status=active\|past\|all, page, limit` | `{ orders: [OrderSummary], meta }` |
| GET | `/orders/active` | | |
| GET | `/orders/:id` | | `{ order: OrderDetail }` with items, bill, timeline, payments, `canCancel`, `canReview`, `isDemoTracking` |
| GET | `/orders/:id/tracking` | | `{ status, estimatedMinutes, cafeLocation, destination, rider: { latitude, longitude, progress, isSimulated:true } \| null, timeline }` |
| POST | `/orders/:id/cancel` | `{ reason? }` | Allowed before `PREPARING`; paid orders are refunded |
| POST | `/orders/:id/reorder` | | Puts available items back in the cart → `{ cart, skippedItems }` |

Status flow: `PENDING_PAYMENT → PLACED → CONFIRMED → PREPARING → READY_FOR_PICKUP → OUT_FOR_DELIVERY → DELIVERED` (+ `CANCELLED`).

## Payments

| Method | Path | Body | Notes |
| --- | --- | --- | --- |
| GET | `/payments/methods` | | Methods enabled on this server |
| POST 🔒 | `/payments/:paymentId/verify` | `{ razorpayOrderId, razorpayPaymentId, razorpaySignature }` | HMAC-SHA256 verified with the key secret → order becomes `PLACED` |
| POST 🔒 | `/payments/:paymentId/failure` | `{ cancelled, reason? }` | Records a failed/cancelled checkout |
| POST 🔒 | `/payments/:paymentId/mock-complete` | `{ outcome: "success"\|"failure"\|"cancel" }` | **Demo provider only** (`MOCK_PAYMENTS=true`) |
| POST 🔒 | `/payments/orders/:orderId/attempts` | `{ method: "RAZORPAY"\|"MOCK" }` | New attempt after a failure |
| POST | `/payments/webhook/razorpay` | raw Razorpay webhook | Verified with `X-Razorpay-Signature`; handles `payment.captured` / `payment.failed` |

## Reviews

| Method | Path | Body |
| --- | --- | --- |
| POST 🔒 | `/orders/:orderId/review` | `{ rating: 1-5, comment? (≤500) }` — only for your **delivered** orders, once |
| GET | `/cafes/:cafeId/reviews` | |
| GET 🔒 | `/me/reviews` | |

## Notifications 🔒

| Method | Path | Body |
| --- | --- | --- |
| POST | `/notifications/devices` | `{ token, platform: "IOS" }` — FCM registration token |
| DELETE | `/notifications/devices/:token` | |
| GET | `/notifications` | `{ notifications, unreadCount, meta }` (in-app inbox) |
| POST | `/notifications/read` | `{ ids? }` — omit to mark all |
| GET / PUT | `/notifications/preferences` | `{ notifyOrderUpdates, notifyPromotions }` |

## Staff / admin

Requires a `CAFE_STAFF`/`ADMIN` user token **or** header `x-admin-key: <ADMIN_API_KEY>`.

| Method | Path | Body |
| --- | --- | --- |
| GET | `/admin/orders` | open orders |
| PATCH | `/admin/orders/:id/status` | `{ status, note? }` — validated by the state machine |

```bash
# move an order by hand (with DEMO_ORDER_PROGRESSION=false)
curl -X PATCH "$API/api/v1/admin/orders/$ORDER_ID/status" \
  -H "x-admin-key: $ADMIN_API_KEY" -H "Content-Type: application/json" -d '{"status":"CONFIRMED"}'
```

## Realtime (Socket.IO)

Connect to the server root, path `/socket.io`, with `auth: { token: <accessToken> }`.

| Direction | Event | Payload |
| --- | --- | --- |
| client → server | `order:subscribe` (with ack) | `orderId` → ack `{ ok, status }` (only your own orders) |
| client → server | `order:unsubscribe` | `orderId` |
| server → client | `order:status` | `{ orderId, status, statusLabel, at, estimatedMinutes }` |
| server → client | `order:location` | `{ orderId, latitude, longitude, progress, isSimulated: true, at }` |
| server → client | `notification` | `{ id, title, body, orderId, createdAt }` |
