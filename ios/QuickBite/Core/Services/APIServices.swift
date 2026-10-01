import Foundation
import NetworkKit

// Each feature talks to the backend through a small protocol, so view models
// can be unit tested with fakes. The live implementations are thin: they only
// describe endpoints; NetworkKit does the transport, auth and retries.

// MARK: - Auth

protocol AuthServicing {
    func register(name: String, email: String, password: String, phone: String?) async throws -> AuthResponse
    func login(email: String, password: String) async throws -> AuthResponse
    func socialLogin(provider: String, identityToken: String, name: String?) async throws -> AuthResponse
    func logout(refreshToken: String?, deviceToken: String?) async
    func me() async throws -> User
    func updateProfile(name: String?, email: String?, phone: String?) async throws -> User
    func deleteAccount() async throws
}

struct AuthService: AuthServicing {
    let client: APIClient

    func register(name: String, email: String, password: String, phone: String?) async throws -> AuthResponse {
        struct Body: Encodable { let name, email, password: String; let phone: String? }
        return try await client.send(Endpoint(path: "/auth/register", method: .post, jsonBody: Body(name: name, email: email, password: password, phone: phone)))
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await client.send(Endpoint(path: "/auth/login", method: .post, jsonBody: ["email": email, "password": password]))
    }

    func socialLogin(provider: String, identityToken: String, name: String?) async throws -> AuthResponse {
        struct Body: Encodable { let provider, identityToken: String; let name: String? }
        return try await client.send(Endpoint(path: "/auth/social", method: .post, jsonBody: Body(provider: provider, identityToken: identityToken, name: name)))
    }

    func logout(refreshToken: String?, deviceToken: String?) async {
        struct Body: Encodable { let refreshToken: String?; let deviceToken: String? }
        guard let endpoint = try? Endpoint<EmptyResponse>(path: "/auth/logout", method: .post, jsonBody: Body(refreshToken: refreshToken, deviceToken: deviceToken)) else { return }
        _ = try? await client.send(endpoint)
    }

    func me() async throws -> User {
        try await client.send(Endpoint<UserResponse>(path: "/auth/me", requiresAuth: true)).user
    }

    func updateProfile(name: String?, email: String?, phone: String?) async throws -> User {
        struct Body: Encodable { let name: String?; let email: String?; let phone: String? }
        return try await client.send(Endpoint<UserResponse>(path: "/auth/me", method: .patch, jsonBody: Body(name: name, email: email, phone: phone), requiresAuth: true)).user
    }

    func deleteAccount() async throws {
        _ = try await client.send(Endpoint<EmptyResponse>(path: "/auth/me", method: .delete, requiresAuth: true))
    }
}

// MARK: - Catalogue

struct SearchFilters: Equatable {
    enum Sort: String, CaseIterable {
        case relevance, popularity, priceLow, priceHigh, rating
        var title: String {
            switch self {
            case .relevance: return "Relevance"
            case .popularity: return "Popularity"
            case .priceLow: return "Price: low to high"
            case .priceHigh: return "Price: high to low"
            case .rating: return "Rating"
            }
        }
    }
    var vegOnly = false
    var category: String?
    var maxPricePaise: Paise?
    var minRating: Double?
    var availableOnly = false
    var sort: Sort = .relevance

    var isDefault: Bool { self == SearchFilters() }
}

protocol CatalogServicing {
    func home(lat: Double, lng: Double) async throws -> HomeFeed
    func cafes(lat: Double, lng: Double, category: String?, minRating: Double?, openNow: Bool, sort: String, page: Int) async throws -> CafeListResponse
    func cafeDetail(id: String, lat: Double, lng: Double) async throws -> CafeDetailResponse
    func search(query: String, filters: SearchFilters, lat: Double, lng: Double, page: Int) async throws -> SearchResponse
    func suggestions() async throws -> SearchSuggestions
}

struct CatalogService: CatalogServicing {
    let client: APIClient

    private func coords(_ lat: Double, _ lng: Double) -> [String: String] {
        ["lat": String(format: "%.5f", lat), "lng": String(format: "%.5f", lng)]
    }

    func home(lat: Double, lng: Double) async throws -> HomeFeed {
        try await client.send(Endpoint(path: "/home", query: coords(lat, lng)))
    }

    func cafes(lat: Double, lng: Double, category: String?, minRating: Double?, openNow: Bool, sort: String, page: Int) async throws -> CafeListResponse {
        var query = coords(lat, lng)
        query["sort"] = sort
        query["page"] = String(page)
        if let category { query["category"] = category }
        if let minRating { query["minRating"] = String(minRating) }
        if openNow { query["openNow"] = "true" }
        return try await client.send(Endpoint(path: "/cafes", query: query))
    }

    func cafeDetail(id: String, lat: Double, lng: Double) async throws -> CafeDetailResponse {
        try await client.send(Endpoint(path: "/cafes/\(id)", query: coords(lat, lng)))
    }

    func search(query: String, filters: SearchFilters, lat: Double, lng: Double, page: Int) async throws -> SearchResponse {
        var params = coords(lat, lng)
        params["q"] = query
        params["page"] = String(page)
        params["sort"] = filters.sort.rawValue
        if filters.vegOnly { params["veg"] = "true" }
        if filters.availableOnly { params["availableOnly"] = "true" }
        if let category = filters.category { params["category"] = category }
        if let max = filters.maxPricePaise { params["maxPrice"] = String(max) }
        if let rating = filters.minRating { params["minRating"] = String(rating) }
        return try await client.send(Endpoint(path: "/search", query: params))
    }

    func suggestions() async throws -> SearchSuggestions {
        try await client.send(Endpoint(path: "/search/suggestions"))
    }
}

// MARK: - Cart (server pricing)

protocol CartServicing {
    /// Replaces the server cart with the local lines and returns server-calculated prices.
    func sync(lines: [CartSyncRequest.Line], couponCode: String?) async throws -> PricedCart
    func reorder(orderId: String) async throws -> PricedCartResponse
}

struct CartService: CartServicing {
    let client: APIClient

    func sync(lines: [CartSyncRequest.Line], couponCode: String?) async throws -> PricedCart {
        let body = CartSyncRequest(items: lines, couponCode: couponCode)
        return try await client.send(Endpoint<PricedCartResponse>(path: "/cart", method: .put, jsonBody: body, requiresAuth: true)).cart
    }

    func reorder(orderId: String) async throws -> PricedCartResponse {
        try await client.send(Endpoint(path: "/orders/\(orderId)/reorder", method: .post, requiresAuth: true))
    }
}

// MARK: - Orders & payments

protocol OrderServicing {
    func placeOrder(addressId: String, paymentMethod: String, idempotencyKey: String) async throws -> PlaceOrderResponse
    func orders(status: String, page: Int) async throws -> OrderListResponse
    func activeOrders() async throws -> [OrderSummary]
    func order(id: String) async throws -> OrderDetail
    func tracking(id: String) async throws -> OrderTracking
    func cancel(id: String, reason: String?) async throws -> OrderDetail
}

struct OrderService: OrderServicing {
    let client: APIClient

    func placeOrder(addressId: String, paymentMethod: String, idempotencyKey: String) async throws -> PlaceOrderResponse {
        let body = PlaceOrderRequest(addressId: addressId, paymentMethod: paymentMethod, idempotencyKey: idempotencyKey)
        // Safe to retry: the idempotency key makes the server return the same order.
        return try await client.send(Endpoint(path: "/orders", method: .post, jsonBody: body, requiresAuth: true, allowsRetry: true))
    }

    func orders(status: String, page: Int) async throws -> OrderListResponse {
        try await client.send(Endpoint(path: "/orders", query: ["status": status, "page": String(page)], requiresAuth: true))
    }

    func activeOrders() async throws -> [OrderSummary] {
        try await client.send(Endpoint<OrderListResponse>(path: "/orders/active", requiresAuth: true)).orders
    }

    func order(id: String) async throws -> OrderDetail {
        try await client.send(Endpoint<OrderDetailResponse>(path: "/orders/\(id)", requiresAuth: true)).order
    }

    func tracking(id: String) async throws -> OrderTracking {
        try await client.send(Endpoint(path: "/orders/\(id)/tracking", requiresAuth: true))
    }

    func cancel(id: String, reason: String?) async throws -> OrderDetail {
        try await client.send(Endpoint<OrderDetailResponse>(path: "/orders/\(id)/cancel", method: .post, jsonBody: ["reason": reason ?? "Cancelled from the app"], requiresAuth: true)).order
    }
}

protocol PaymentServicing {
    func methods() async throws -> [PaymentMethodOption]
    func completeMock(paymentId: String, outcome: String) async throws -> OrderDetail
    func verifyRazorpay(paymentId: String, orderId: String, razorpayPaymentId: String, signature: String) async throws -> OrderDetail
    func reportFailure(paymentId: String, cancelled: Bool, reason: String?) async throws -> OrderDetail
    func newAttempt(orderId: String, method: String) async throws -> PaymentInfo
}

struct PaymentService: PaymentServicing {
    let client: APIClient

    func methods() async throws -> [PaymentMethodOption] {
        try await client.send(Endpoint<PaymentMethodsResponse>(path: "/payments/methods")).methods
    }

    func completeMock(paymentId: String, outcome: String) async throws -> OrderDetail {
        try await client.send(Endpoint<OrderDetailResponse>(path: "/payments/\(paymentId)/mock-complete", method: .post, jsonBody: ["outcome": outcome], requiresAuth: true)).order
    }

    func verifyRazorpay(paymentId: String, orderId: String, razorpayPaymentId: String, signature: String) async throws -> OrderDetail {
        let body = ["razorpayOrderId": orderId, "razorpayPaymentId": razorpayPaymentId, "razorpaySignature": signature]
        return try await client.send(Endpoint<OrderDetailResponse>(path: "/payments/\(paymentId)/verify", method: .post, jsonBody: body, requiresAuth: true, allowsRetry: true)).order
    }

    func reportFailure(paymentId: String, cancelled: Bool, reason: String?) async throws -> OrderDetail {
        struct Body: Encodable { let cancelled: Bool; let reason: String? }
        return try await client.send(Endpoint<OrderDetailResponse>(path: "/payments/\(paymentId)/failure", method: .post, jsonBody: Body(cancelled: cancelled, reason: reason), requiresAuth: true)).order
    }

    func newAttempt(orderId: String, method: String) async throws -> PaymentInfo {
        try await client.send(Endpoint<PaymentAttemptResponse>(path: "/payments/orders/\(orderId)/attempts", method: .post, jsonBody: ["method": method], requiresAuth: true)).payment
    }
}

// MARK: - Addresses

protocol AddressServicing {
    func list() async throws -> [Address]
    func create(_ input: AddressInput) async throws -> Address
    func update(id: String, _ input: AddressInput) async throws -> Address
    func delete(id: String) async throws
}

struct AddressService: AddressServicing {
    let client: APIClient

    func list() async throws -> [Address] {
        try await client.send(Endpoint<AddressListResponse>(path: "/addresses", requiresAuth: true)).addresses
    }

    func create(_ input: AddressInput) async throws -> Address {
        try await client.send(Endpoint<AddressResponse>(path: "/addresses", method: .post, jsonBody: input, requiresAuth: true)).address
    }

    func update(id: String, _ input: AddressInput) async throws -> Address {
        try await client.send(Endpoint<AddressResponse>(path: "/addresses/\(id)", method: .put, jsonBody: input, requiresAuth: true)).address
    }

    func delete(id: String) async throws {
        _ = try await client.send(Endpoint<EmptyResponse>(path: "/addresses/\(id)", method: .delete, requiresAuth: true))
    }
}

// MARK: - Reviews

protocol ReviewServicing {
    func submit(orderId: String, rating: Int, comment: String?) async throws -> Review
    func cafeReviews(cafeId: String, page: Int) async throws -> ReviewListResponse
    func myReviews(page: Int) async throws -> ReviewListResponse
}

struct ReviewService: ReviewServicing {
    let client: APIClient

    func submit(orderId: String, rating: Int, comment: String?) async throws -> Review {
        struct Body: Encodable { let rating: Int; let comment: String? }
        return try await client.send(Endpoint<ReviewResponse>(path: "/orders/\(orderId)/review", method: .post, jsonBody: Body(rating: rating, comment: comment), requiresAuth: true)).review
    }

    func cafeReviews(cafeId: String, page: Int) async throws -> ReviewListResponse {
        try await client.send(Endpoint(path: "/cafes/\(cafeId)/reviews", query: ["page": String(page)]))
    }

    func myReviews(page: Int) async throws -> ReviewListResponse {
        try await client.send(Endpoint(path: "/me/reviews", query: ["page": String(page)], requiresAuth: true))
    }
}

// MARK: - Notifications

protocol NotificationServicing {
    func registerDevice(token: String) async throws
    func unregisterDevice(token: String) async
    func list(page: Int) async throws -> NotificationListResponse
    func markAllRead() async
    func preferences() async throws -> NotificationPreferences
    func updatePreferences(_ prefs: NotificationPreferences) async throws -> NotificationPreferences
}

struct NotificationService: NotificationServicing {
    let client: APIClient

    func registerDevice(token: String) async throws {
        struct Response: Decodable { let registered: Bool }
        _ = try await client.send(Endpoint<Response>(path: "/notifications/devices", method: .post, jsonBody: ["token": token, "platform": "IOS"], requiresAuth: true))
    }

    func unregisterDevice(token: String) async {
        let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        _ = try? await client.send(Endpoint<EmptyResponse>(path: "/notifications/devices/\(encoded)", method: .delete, requiresAuth: true))
    }

    func list(page: Int) async throws -> NotificationListResponse {
        try await client.send(Endpoint(path: "/notifications", query: ["page": String(page)], requiresAuth: true))
    }

    func markAllRead() async {
        guard let endpoint = try? Endpoint<EmptyResponse>(path: "/notifications/read", method: .post, jsonBody: [String: String](), requiresAuth: true) else { return }
        _ = try? await client.send(endpoint)
    }

    func preferences() async throws -> NotificationPreferences {
        try await client.send(Endpoint(path: "/notifications/preferences", requiresAuth: true))
    }

    func updatePreferences(_ prefs: NotificationPreferences) async throws -> NotificationPreferences {
        try await client.send(Endpoint(path: "/notifications/preferences", method: .put, jsonBody: prefs, requiresAuth: true))
    }
}

// MARK: - Health

struct HealthService {
    /// A client whose base URL is the server root (/health lives outside /api/v1).
    let rootClient: APIClient
    func check() async throws -> HealthResponse {
        try await rootClient.send(Endpoint(path: "/health", allowsRetry: false, timeout: 8))
    }
}
