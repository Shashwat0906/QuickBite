#if DEBUG
import Foundation

/// In-process fake backend used ONLY by UI tests (launch argument `-uiTesting`).
///
/// It answers the same JSON contract as the real API so the app runs its
/// normal code paths (NetworkKit, decoding, view models) — just without a
/// network or database. Never compiled into Release builds.
final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = StubBackend.shared.handle(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class StubBackend {
    static let shared = StubBackend()

    private let lock = NSLock()
    private var cartLines: [CartSyncRequest.Line] = []
    private var coupon: String?
    private var orders: [String: OrderDetail] = [:]
    private var addresses: [Address] = [
        Address(id: "addr-1", label: "Home", line1: "B-12, Barakhamba Road", line2: nil, city: "New Delhi", pincode: "110001", latitude: 28.629, longitude: 77.225, isDefault: true),
    ]
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: Fixtures

    static let user = User(id: "user-1", name: "Test User", email: "test@quickbite.app", phone: nil, authProvider: "EMAIL", notifyOrderUpdates: true, notifyPromotions: false)

    static func cafe(id: String, name: String, featured: Bool, minutes: Int) -> Cafe {
        Cafe(id: id, name: name, slug: id, description: "Specialty coffee and fresh bakes.", imageUrl: "https://stub.quickbite.test/img.jpg", bannerUrl: "https://stub.quickbite.test/banner.jpg",
             cuisines: ["coffee", "bakery"], rating: 4.6, ratingCount: 120, deliveryFeePaise: 2500, minOrderPaise: 9900, isOpenNow: true, opensAt: "00:00", closesAt: "23:59",
             isFeatured: featured, latitude: 28.6328, longitude: 77.2197, addressLine: "Connaught Place", phone: "+911140001111", distanceKm: 0.6, deliveryMinutes: minutes)
    }

    static let brew = cafe(id: "cafe-1", name: "Brew & Bloom", featured: true, minutes: 12)
    static let chai = cafe(id: "cafe-2", name: "Chai Chowk", featured: false, minutes: 15)

    static let sizeGroup = CustomizationGroup(id: "grp-size", name: "Size", minSelect: 1, maxSelect: 1, options: [
        CustomizationOption(id: "opt-regular", name: "Regular", extraPricePaise: 0, isAvailable: true),
        CustomizationOption(id: "opt-large", name: "Large", extraPricePaise: 4000, isAvailable: true),
    ])

    static let items: [MenuItem] = [
        MenuItem(id: "item-1", cafeId: "cafe-1", categoryId: "cat-1", name: "Signature Cappuccino", description: "Double-shot espresso with velvety microfoam.", imageUrl: "https://stub.quickbite.test/1.jpg",
                 pricePaise: 18900, diet: .veg, isAvailable: true, isBestseller: true, popularity: 900, cafeName: "Brew & Bloom", customizations: [sizeGroup]),
        MenuItem(id: "item-2", cafeId: "cafe-1", categoryId: "cat-2", name: "Butter Croissant", description: "Flaky and buttery, baked every morning.", imageUrl: "https://stub.quickbite.test/2.jpg",
                 pricePaise: 14900, diet: .veg, isAvailable: true, isBestseller: false, popularity: 700, cafeName: "Brew & Bloom", customizations: []),
        MenuItem(id: "item-3", cafeId: "cafe-1", categoryId: "cat-2", name: "Almond Croissant", description: "Sold out for today.", imageUrl: "https://stub.quickbite.test/3.jpg",
                 pricePaise: 17900, diet: .egg, isAvailable: false, isBestseller: false, popularity: 100, cafeName: "Brew & Bloom", customizations: []),
    ]

    // MARK: Routing

    func handle(_ request: URLRequest) -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        guard let url = request.url else { return error(400, "BAD_REQUEST", "No URL") }
        let path = url.path.replacingOccurrences(of: "/api/v1", with: "")
        let method = request.httpMethod ?? "GET"
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let parts = path.split(separator: "/").map(String.init)

        if route(method, parts, "GET", "health") != nil {
            return ok(["status": "ok", "database": "ok", "version": "stub", "features": ["razorpay": false, "mockPayments": true, "fcm": false, "demoOrderProgression": true, "socialLoginDemo": true]])
        } else if route(method, parts, "POST", "auth/login") != nil {
            let password = json["password"] as? String ?? ""
            guard password == "Passw0rd!" else { return error(401, "INVALID_CREDENTIALS", "Incorrect email or password") }
            return authResponse()
        } else if route(method, parts, "POST", "auth/register") != nil || route(method, parts, "POST", "auth/social") != nil {
            return authResponse(status: method == "POST" && parts.last == "register" ? 201 : 200)
        } else if route(method, parts, "GET", "auth/me") != nil {
            return ok(["user": encode(Self.user)])
        } else if route(method, parts, "GET", "home") != nil {
            return ok(encode(HomeFeed(
                offers: [Offer(code: "WELCOME50", description: "50% off up to ₹100 on your first order", type: "PERCENT", value: 50, minOrderPaise: 19900, maxDiscountPaise: 10000)],
                featuredCafes: [Self.brew], nearbyCafes: [Self.brew, Self.chai], categories: ["Coffee", "Bakery"],
                popularDishes: Self.items, bestsellers: [Self.items[0]], fastestDeliveryMinutes: 12)))
        } else if route(method, parts, "GET", "cafes") != nil {
            return ok(["cafes": [encode(Self.brew), encode(Self.chai)], "meta": meta(total: 2)])
        } else if route(method, parts, "GET", "cafes/:_/reviews") != nil {
            return ok(["reviews": [], "distribution": ["1": 0, "2": 0, "3": 0, "4": 0, "5": 0], "meta": meta(total: 0)])
        } else if let p = route(method, parts, "GET", "cafes/:id") {
            let id = p[0]
            let cafe = id == Self.chai.id ? Self.chai : Self.brew
            return ok(encode(CafeDetailResponse(cafe: cafe, menu: [
                MenuSection(id: "cat-1", name: "Coffee", items: [Self.items[0]]),
                MenuSection(id: "cat-2", name: "Bakery", items: [Self.items[1], Self.items[2]]),
            ])))
        } else if route(method, parts, "GET", "search/suggestions") != nil {
            return ok(["suggestions": ["Cappuccino", "Croissant"], "categories": ["Coffee", "Bakery"]])
        } else if route(method, parts, "GET", "search") != nil {
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value?.lowercased() ?? ""
            let matches = Self.items.filter { q.isEmpty || $0.name.lowercased().contains(q) }
            return ok(["query": q, "cafes": [], "items": matches.map(encode), "meta": meta(total: matches.count)])
        } else if route(method, parts, "PUT", "cart") != nil {
            let lines = (json["items"] as? [[String: Any]] ?? []).compactMap { line -> CartSyncRequest.Line? in
                guard let id = line["menuItemId"] as? String, let qty = line["quantity"] as? Int else { return nil }
                return .init(menuItemId: id, quantity: qty, optionIds: line["optionIds"] as? [String] ?? [])
            }
            cartLines = lines
            coupon = json["couponCode"] as? String
            return ok(["cart": encode(pricedCart())])
        } else if route(method, parts, "GET", "addresses") != nil {
            return ok(["addresses": addresses.map(encode)])
        } else if route(method, parts, "POST", "addresses") != nil {
            let address = Address(id: "addr-\(addresses.count + 1)", label: json["label"] as? String ?? "Other", line1: json["line1"] as? String ?? "",
                                  line2: json["line2"] as? String, city: json["city"] as? String ?? "", pincode: json["pincode"] as? String ?? "",
                                  latitude: json["latitude"] as? Double ?? 28.63, longitude: json["longitude"] as? Double ?? 77.22, isDefault: addresses.isEmpty)
            addresses.append(address)
            return (201, data(["address": encode(address)]))
        } else if route(method, parts, "GET", "payments/methods") != nil {
            return ok(["methods": [
                ["id": "MOCK", "title": "Demo payment", "subtitle": "Simulated — no real money moves", "isMock": true],
                ["id": "CASH_ON_DELIVERY", "title": "Cash on delivery", "subtitle": "Pay when your order arrives", "isMock": false],
            ]])
        } else if route(method, parts, "POST", "orders") != nil {
            return placeOrder(paymentMethod: json["paymentMethod"] as? String ?? "MOCK")
        } else if let p = route(method, parts, "POST", "payments/:paymentId/mock-complete") {
            let paymentId = p[0]
            guard let order = orders.values.first(where: { $0.payments.contains { $0.id == paymentId } }) else { return error(404, "NOT_FOUND", "Payment not found") }
            let updated = makeOrder(id: order.id, number: order.orderNumber, status: .placed, method: .mock, paymentStatus: .succeeded)
            orders[order.id] = updated
            return ok(["order": encode(updated)])
        } else if route(method, parts, "GET", "orders/active") != nil {
            return ok(["orders": orders.values.filter { $0.status.isActive }.map { encode(summary($0)) }])
        } else if route(method, parts, "GET", "orders") != nil {
            return ok(["orders": orders.values.filter { $0.status != .pendingPayment }.map { encode(summary($0)) }, "meta": meta(total: orders.count)])
        } else if let p = route(method, parts, "GET", "orders/:id/tracking") {
            let id = p[0]
            guard let order = orders[id] else { return error(404, "NOT_FOUND", "Order not found") }
            return ok(encode(OrderTracking(orderId: id, status: order.status, estimatedMinutes: 14, placedAt: order.createdAt,
                                           cafeLocation: Coordinate(latitude: 28.6328, longitude: 77.2197), destination: Coordinate(latitude: 28.629, longitude: 77.225),
                                           rider: nil, isDemoTracking: true, timeline: order.timeline)))
        } else if let p = route(method, parts, "GET", "orders/:id") {
            let id = p[0]
            guard let order = orders[id] else { return error(404, "NOT_FOUND", "Order not found") }
            return ok(["order": encode(order)])
        } else if let p = route(method, parts, "POST", "orders/:id/cancel") {
            let id = p[0]
            guard let order = orders[id] else { return error(404, "NOT_FOUND", "Order not found") }
            let updated = makeOrder(id: id, number: order.orderNumber, status: .cancelled, method: order.paymentMethod ?? .mock, paymentStatus: .refunded)
            orders[id] = updated
            return ok(["order": encode(updated)])
        } else if route(method, parts, "GET", "notifications/preferences") != nil {
            return ok(["notifyOrderUpdates": true, "notifyPromotions": false])
        } else if route(method, parts, "GET", "notifications") != nil {
            return ok(["notifications": [], "unreadCount": 0, "meta": meta(total: 0)])
        } else if route(method, parts, "POST", "notifications/devices") != nil {
            return (201, data(["registered": true]))
        } else if route(method, parts, "GET", "me/reviews") != nil {
            return ok(["reviews": [], "meta": meta(total: 0)])
        } else if route(method, parts, "POST", "auth/logout") != nil || route(method, parts, "POST", "notifications/read") != nil {
            return (204, Data())
        } else {
            return error(404, "ROUTE_NOT_FOUND", "Stub has no route for \(method) \(path)")
        }
    }

    /// Matches "cafes/:id/reviews"-style patterns; returns captured params.
    private func route(_ method: String, _ parts: [String], _ expectedMethod: String, _ pattern: String) -> [String]? {
        let segments = pattern.split(separator: "/").map(String.init)
        guard method == expectedMethod, segments.count == parts.count else { return nil }
        var params: [String] = []
        for (segment, part) in zip(segments, parts) {
            if segment.hasPrefix(":") {
                if segment != ":_" { params.append(part) }
            } else if segment != part {
                return nil
            }
        }
        return params
    }

    // MARK: Builders

    private func pricedCart() -> PricedCart {
        let priced: [PricedCartLine] = cartLines.compactMap { line in
            guard let item = Self.items.first(where: { $0.id == line.menuItemId }) else { return nil }
            let extras = item.customizations.flatMap(\.options).filter { line.optionIds.contains($0.id) }.map(\.extraPricePaise)
            let unit = PricingCalculator.unitPrice(base: item.pricePaise, optionExtras: extras)
            return PricedCartLine(id: UUID().uuidString, menuItem: item, quantity: line.quantity, optionIds: line.optionIds, unitPricePaise: unit, lineTotalPaise: unit * line.quantity, issue: nil)
        }
        let subtotal = priced.reduce(0) { $0 + $1.lineTotalPaise }
        var couponResult: CouponResult?
        var discount = 0
        if let coupon {
            let offer = Offer(code: "WELCOME50", description: "", type: "PERCENT", value: 50, minOrderPaise: 19900, maxDiscountPaise: 10000)
            if coupon.uppercased() == "WELCOME50", case .valid(let d) = CouponRules.evaluate(offer, subtotal: subtotal) {
                discount = d
                couponResult = CouponResult(code: "WELCOME50", isValid: true, message: "50% off up to ₹100 on your first order", discountPaise: d)
            } else {
                couponResult = CouponResult(code: coupon.uppercased(), isValid: false, message: "This coupon is not valid", discountPaise: 0)
            }
        }
        let bill = PricingCalculator.bill(lines: priced.map { .init(unitPricePaise: $0.unitPricePaise, quantity: $0.quantity) }, deliveryFee: 2500, minOrder: 9900, discount: discount)
        return PricedCart(cafe: priced.isEmpty ? nil : Self.brew, lines: priced, bill: priced.isEmpty ? nil : bill, coupon: couponResult, issues: [], canCheckout: !priced.isEmpty)
    }

    private func placeOrder(paymentMethod: String) -> (Int, Data) {
        let cart = pricedCart()
        guard cart.canCheckout else { return error(422, "CART_INVALID", "Your cart is empty") }
        let id = UUID().uuidString.lowercased()
        let method = PaymentProvider(rawValue: paymentMethod) ?? .mock
        let order = makeOrder(id: id, number: "QB-TEST\(orders.count + 1)", status: method == .cashOnDelivery ? .placed : .pendingPayment,
                              method: method, paymentStatus: method == .cashOnDelivery ? .pending : .created, cart: cart)
        orders[id] = order
        cartLines = []
        coupon = nil
        return (201, data(["order": encode(order), "payment": encode(order.payments[0]), "replayed": false]))
    }

    private var lastCart: PricedCart?

    private func makeOrder(id: String, number: String, status: OrderStatus, method: PaymentProvider, paymentStatus: PaymentStatus, cart: PricedCart? = nil) -> OrderDetail {
        if let cart { lastCart = cart }
        let cart = cart ?? lastCart
        let bill = cart?.bill ?? Bill(subtotalPaise: 0, discountPaise: 0, deliveryFeePaise: 0, taxPaise: 0, totalPaise: 0)
        let lines = (cart?.lines ?? []).map {
            OrderLine(id: UUID().uuidString, menuItemId: $0.menuItem.id, name: $0.menuItem.name, quantity: $0.quantity, unitPricePaise: $0.unitPricePaise, lineTotalPaise: $0.lineTotalPaise, options: [])
        }
        let created = orders[id]?.createdAt ?? Date()
        var timeline = [TimelineEvent(status: .placed, label: "Order placed", note: nil, at: created)]
        if status == .cancelled { timeline.append(TimelineEvent(status: .cancelled, label: "Cancelled", note: "Cancelled by customer", at: Date())) }
        let payment = PaymentInfo(id: orders[id]?.payments.first?.id ?? "pay-\(id.prefix(6))", provider: method, status: paymentStatus, amountPaise: bill.totalPaise,
                                  providerOrderId: "mock_order", failureReason: nil, createdAt: created, razorpayKeyId: nil, isMock: method == .mock)
        return OrderDetail(id: id, orderNumber: number, status: status, statusLabel: status.title,
                           cafe: OrderCafe(id: Self.brew.id, name: Self.brew.name, imageUrl: Self.brew.imageUrl, phone: Self.brew.phone, latitude: 28.6328, longitude: 77.2197, addressLine: Self.brew.addressLine),
                           totalPaise: bill.totalPaise, createdAt: created, estimatedMinutes: 14, isReviewed: false, items: lines, bill: bill, couponCode: nil,
                           deliveryAddress: DeliveryAddressSnapshot(label: "Home", line1: "B-12, Barakhamba Road", line2: nil, city: "New Delhi", pincode: "110001", latitude: 28.629, longitude: 77.225, redacted: nil),
                           timeline: timeline, payments: [payment], isDemoTracking: true, cancelReason: status == .cancelled ? "Cancelled by customer" : nil,
                           deliveredAt: nil, canCancel: [.pendingPayment, .placed, .confirmed].contains(status), canReview: status == .delivered, paymentMethod: method)
    }

    private func summary(_ o: OrderDetail) -> OrderSummary {
        OrderSummary(id: o.id, orderNumber: o.orderNumber, status: o.status, statusLabel: o.statusLabel, cafe: OrderCafeSummary(id: Self.brew.id, name: Self.brew.name, imageUrl: Self.brew.imageUrl),
                     totalPaise: o.totalPaise, itemCount: o.items.reduce(0) { $0 + $1.quantity }, itemsPreview: o.items.map { "\($0.quantity) × \($0.name)" }.joined(separator: ", "),
                     createdAt: o.createdAt, estimatedMinutes: o.estimatedMinutes, isReviewed: o.isReviewed)
    }

    private func authResponse(status: Int = 200) -> (Int, Data) {
        let tokens = AuthTokens(accessToken: "stub-access", refreshToken: "stub-refresh", expiresAt: Date().addingTimeInterval(3600))
        return (status, data(["user": encode(Self.user), "tokens": encode(tokens)]))
    }

    private func meta(total: Int) -> [String: Any] {
        ["page": 1, "limit": 20, "total": total, "totalPages": 1, "hasMore": false]
    }

    private func encode<T: Encodable>(_ value: T) -> Any {
        guard let data = try? encoder.encode(value) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? [:]
    }

    private func ok(_ object: Any) -> (Int, Data) { (200, data(object)) }

    private func error(_ status: Int, _ code: String, _ message: String) -> (Int, Data) {
        (status, data(["error": ["code": code, "message": message]]))
    }

    private func data(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
#endif
