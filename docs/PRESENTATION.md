# QuickBite — demo script, résumé bullets & interview notes

## Résumé entry (pick 3–4 bullets)

**QuickBite — café ordering & 10-minute delivery app (iOS, Swift/UIKit + Node.js)** · github.com/Shashwat0906/QuickBite

- Built a production-style iOS app in **Swift and programmatic UIKit** with **MVVM + Coordinator**
  navigation, dependency injection and protocol-based services, covering 11 screens from
  onboarding to live order tracking.
- Designed two reusable **Swift Packages**: *NetworkKit* (generic async/await API client with typed
  endpoints, automatic JWT refresh, retry with backoff and in-flight request de-duplication) and
  *DesignKit* (design tokens, UIKit components, NSCache + ImageIO-downsampling image pipeline).
- Implemented **real-time order tracking** by writing a Socket.IO client on
  `URLSessionWebSocketTask`, with reconnection, room subscriptions and a polling fallback, shown on
  a **MapKit** map and step tracker.
- Built the **Node.js/Express + PostgreSQL (Prisma)** backend: JWT auth with rotating refresh tokens,
  server-side pricing/coupon validation, an order state machine, idempotent order creation,
  Razorpay (test mode) signature verification and FCM push.
- Added **offline support** (Core Data cart, cached menus), **Objective-C interop** (bridged price
  formatter), and **CI/CD** with GitHub Actions + fastlane running backend integration tests on
  PostgreSQL and iOS unit/UI tests on macOS runners.

*(Only add measured performance numbers — see PERFORMANCE.md — e.g. "cut image memory by X% with
ImageIO downsampling (measured in Instruments)".)*

## 5-minute live demo

Before the interview: open `https://<service>.onrender.com/health` to wake the free server,
run the app once, and make sure the cart is empty.

1. **Launch** → splash animation → onboarding (3 pages) → *Browse as guest*.
   *"Coordinator decides splash → onboarding → tabs; onboarding is shown once."*
2. **Home**: pull to refresh, skeletons, offer carousel (tap = copies coupon), categories, featured cafés.
   *"One `/home` request; cached to disk so it shows instantly — even offline."*
3. **Café** (Brew & Bloom): toggle *Veg only*, jump menu, tap **Signature Cappuccino** →
   customisation sheet (Large + Oat milk) — price updates live → add. Add a croissant with ADD/+.
   Try another café → "Replace cart?" dialog.
4. **Cart**: +/−, swipe to delete, *Edit* customisation, coupon **WELCOME50**.
   *"Local Core Data cart works as a guest; once signed in the server re-prices everything —
   the app never sends prices."*
5. **Checkout** → sign in (Sign in with Apple, or demo@quickbite.app) → address with map pin →
   **Demo payment** (labelled) → *Simulate success* (also show *Simulate failure* → retry).
   *"Place order uses an idempotency key — double taps or retries can't create two orders."*
6. **Tracking**: watch PLACED → CONFIRMED → … live (Socket.IO). Point out the **DEMO TRACKING**
   badge: *"there's no rider app, so the backend simulates the rider and the UI says so."*
7. **Orders → Past** → *Rate* → *Reorder*. **Profile** → dark mode, server & diagnostics, delete account.

## Questions you should be ready for

| Question | Short answer |
| --- | --- |
| Why Coordinators? | View controllers stay reusable and testable; navigation (including modal sub-flows like auth/checkout) lives in one place; deep links/push open screens through the same router. |
| How do view models update the UI? | Simple closures (`onChange`) on `@MainActor` view models; Combine only where it clearly helps — debouncing search keystrokes. |
| How is the token refreshed? | NetworkKit catches 401, asks the `AuthTokenProvider` to refresh once (single-flight `Task` so parallel 401s share it) and replays the request; a failed refresh signs the user out. |
| Why compute prices on the server? | The client can be modified; the server reads prices from the DB, validates options/stock/coupons and returns the bill. The app's estimate uses the same formula only for display. |
| What stops duplicate orders? | Unique `(userId, idempotencyKey)` in Postgres; the app reuses one key per checkout attempt; retries return the original order. |
| How does the image cache work? | `NSCache` of decoded, downsampled images (cost = bytes) + `URLCache` on disk; concurrent loads for the same URL share a task; cells cancel on reuse; prefetching warms upcoming rows. |
| How did you test it? | View models with protocol fakes, Core Data with an in-memory store, NetworkKit with a mock transport, UI tests against an in-process stub backend (`-uiTesting`), backend integration tests against real PostgreSQL + Socket.IO in CI. |
| Objective-C? | `QBPriceFormatter` (Indian digit grouping) exposed through a bridging header and wrapped by Swift `Money`; tested from Swift. |
| What would you do next? | Real rider app + location streaming, Apple Pay, background order refresh, snapshot tests, analytics, accessibility audit with VoiceOver users, App Store release. |
