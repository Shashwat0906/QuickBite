# Performance & profiling

> **No invented numbers.** This page explains what was optimised and *how to measure it*. The
> results table is deliberately empty until you record real measurements on your Mac with
> Instruments — fill it in before quoting figures in an interview or on a résumé.

## What's already optimised (and why)

| Area | Technique | Where |
| --- | --- | --- |
| Image memory | ImageIO **downsampling** to the cell's size instead of decoding full-resolution photos (a 1600 px JPEG decodes to ~10 MB; a 300 px thumbnail to well under 1 MB) | `DesignKit/ImagePipeline.decode` |
| Image re-downloads | Two-level cache: `NSCache` (decoded images, cost-limited to 80 MB, auto-purged on memory warnings) + `URLCache` on disk (200 MB) | `ImagePipeline` |
| Duplicate image requests | In-flight de-duplication: 5 cells asking for the same photo share one download | `ImagePipeline.image(for:)` |
| Scroll smoothness | `UICollectionViewDataSourcePrefetching` warms images before cells appear; cells cancel their load on reuse | `HomeViewController`, `RemoteImageView` |
| Duplicate API calls | Identical concurrent GETs share one `Task` | `NetworkKit/InFlightRequests` |
| Typing | Search debounced by 300 ms (Combine) — one request per pause, not per keystroke | `SearchViewModel` |
| Cart taps | Server sync debounced by 400 ms — `+ + +` sends one request | `CartViewModel` |
| Main thread | Networking, JSON decoding, image decoding and cache writes run off the main thread; view models only mutate UI state on `@MainActor` | throughout |
| Cold start offline | Last home feed / menus are read from disk and shown immediately, then refreshed | `ResponseCache`, `HomeViewModel` |

## How to measure (Xcode 16, iPhone simulator or device)

Use a **device** for meaningful CPU/GPU numbers; the simulator is fine for memory trends.

### 1. Memory — image cache behaviour
1. Product → Profile (⌘I) → **Allocations** template.
2. Launch, scroll the Home feed top→bottom 3 times, open 3 cafés, return.
3. Note *Persistent Bytes* at the end and the peak.
4. Debug → Simulate Memory Warning: `NSCache` should release decoded images (drop in persistent bytes).
5. Compare against a build with `targetSize: nil` in `RemoteImageView.setImage` to show the downsampling win.

### 2. Leaks
1. **Leaks** template → walk through: login → café → add to cart → checkout (demo payment) → tracking → back.
2. Expect zero leaks; coordinators/view controllers should deallocate when popped (closures use `[weak self]`).

### 3. Scrolling / hitches
1. **Animation Hitches** template (device) → fling the Home feed and a café menu for ~10 s.
2. Record *hitch time ratio* (ms/s). Apple's guidance: < 5 ms/s is good.

### 4. Launch time
1. **App Launch** template → record time to first frame (cold launch, after a reboot or with the app removed from memory).

### 5. Network
1. **Network** template (or Xcode's Network report) → open Home twice quickly: only one `/home` request should be in flight (de-duplication). Type "latte" in Search: one `/search` request.

## Results (fill in with your own measurements)

| Metric | Device / iOS | Before | After | Notes |
| --- | --- | --- | --- | --- |
| Peak memory scrolling Home ×3 | | | | |
| Persistent memory after memory warning | | | | |
| Hitch time ratio — Home fling | | | | |
| Cold launch → first frame | | | | |
| `/search` requests while typing "latte" | | | | expected: 1 |
| Leaks in checkout flow | | | | expected: 0 |
