import Foundation
import NetworkKit
@testable import QuickBite

// MARK: - Fixtures

enum Fixtures {
    static let user = User(id: "u1", name: "Asha Verma", email: "asha@test.dev", phone: nil, authProvider: "EMAIL", notifyOrderUpdates: true, notifyPromotions: false)
    static let tokens = AuthTokens(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(900))

    static func cafe(id: String = "c1", name: String = "Brew & Bloom", fee: Paise = 2500, minOrder: Paise = 9900) -> Cafe {
        Cafe(id: id, name: name, slug: id, description: "", imageUrl: "https://x/y.jpg", bannerUrl: "https://x/b.jpg", cuisines: ["coffee"], rating: 4.5, ratingCount: 10,
             deliveryFeePaise: fee, minOrderPaise: minOrder, isOpenNow: true, opensAt: "00:00", closesAt: "23:59", isFeatured: true,
             latitude: 28.6, longitude: 77.2, addressLine: "CP", phone: "+911100000000", distanceKm: 1.2, deliveryMinutes: 12)
    }

    static let size = CustomizationGroup(id: "g-size", name: "Size", minSelect: 1, maxSelect: 1, options: [
        CustomizationOption(id: "o-reg", name: "Regular", extraPricePaise: 0, isAvailable: true),
        CustomizationOption(id: "o-large", name: "Large", extraPricePaise: 4000, isAvailable: true),
    ])

    static let extras = CustomizationGroup(id: "g-extra", name: "Extras", minSelect: 0, maxSelect: 2, options: [
        CustomizationOption(id: "o-shot", name: "Extra shot", extraPricePaise: 4000, isAvailable: true),
        CustomizationOption(id: "o-oat", name: "Oat milk", extraPricePaise: 5000, isAvailable: true),
        CustomizationOption(id: "o-syrup", name: "Syrup", extraPricePaise: 3000, isAvailable: false),
    ])

    static func item(id: String = "i1", cafeId: String = "c1", price: Paise = 18900, customizable: Bool = false, available: Bool = true) -> MenuItem {
        MenuItem(id: id, cafeId: cafeId, categoryId: "cat", name: "Item \(id)", description: "", imageUrl: "https://x/i.jpg", pricePaise: price, diet: .veg,
                 isAvailable: available, isBestseller: false, popularity: 0, cafeName: nil, customizations: customizable ? [size, extras] : [])
    }

    static let address = Address(id: "a1", label: "Home", line1: "12 Main St", line2: nil, city: "Delhi", pincode: "110001", latitude: 28.6, longitude: 77.2, isDefault: true)

    static func pricedCart(lines: [PricedCartLine] = [], canCheckout: Bool = true, issues: [CartIssue] = [], coupon: CouponResult? = nil) -> PricedCart {
        PricedCart(cafe: cafe(), lines: lines, bill: Bill(subtotalPaise: 37800, discountPaise: 0, deliveryFeePaise: 2500, taxPaise: 1890, totalPaise: 42190),
                   coupon: coupon, issues: issues, canCheckout: canCheckout)
    }

    static func order(status: OrderStatus = .pendingPayment, provider: PaymentProvider = .mock) -> OrderDetail {
        let payment = PaymentInfo(id: "p1", provider: provider, status: .created, amountPaise: 42190, providerOrderId: "mock_1", failureReason: nil, createdAt: Date(), razorpayKeyId: nil, isMock: provider == .mock)
        return OrderDetail(id: "o1", orderNumber: "QB-TEST1", status: status, statusLabel: status.title, cafe: nil, totalPaise: 42190, createdAt: Date(), estimatedMinutes: 14,
                           isReviewed: false, items: [], bill: Bill(subtotalPaise: 37800, discountPaise: 0, deliveryFeePaise: 2500, taxPaise: 1890, totalPaise: 42190),
                           couponCode: nil, deliveryAddress: nil, timeline: [], payments: [payment], isDemoTracking: true, cancelReason: nil, deliveredAt: nil,
                           canCancel: true, canReview: false, paymentMethod: provider)
    }
}

// MARK: - Fakes

final class FakeAuthService: AuthServicing {
    var loginResult: Result<AuthResponse, Error> = .success(AuthResponse(user: Fixtures.user, tokens: Fixtures.tokens, isDemo: false))
    private(set) var loginCalls = 0
    private(set) var registerCalls = 0

    func register(name: String, email: String, password: String, phone: String?) async throws -> AuthResponse {
        registerCalls += 1
        return try loginResult.get()
    }
    func login(email: String, password: String) async throws -> AuthResponse {
        loginCalls += 1
        return try loginResult.get()
    }
    func socialLogin(provider: String, identityToken: String, name: String?) async throws -> AuthResponse { try loginResult.get() }
    func logout(refreshToken: String?, deviceToken: String?) async {}
    func me() async throws -> User { Fixtures.user }
    func updateProfile(name: String?, email: String?, phone: String?) async throws -> User { Fixtures.user }
    func deleteAccount() async throws {}
}

final class FakeCatalogService: CatalogServicing {
    private(set) var searchQueries: [String] = []
    var searchResponse = SearchResponse(query: "", cafes: [], items: [Fixtures.item()], meta: PageMeta(page: 1, limit: 20, total: 1, totalPages: 1, hasMore: false))

    func home(lat: Double, lng: Double) async throws -> HomeFeed { throw APIError.offline }
    func cafes(lat: Double, lng: Double, category: String?, minRating: Double?, openNow: Bool, sort: String, page: Int) async throws -> CafeListResponse { throw APIError.offline }
    func cafeDetail(id: String, lat: Double, lng: Double) async throws -> CafeDetailResponse { throw APIError.offline }
    func search(query: String, filters: SearchFilters, lat: Double, lng: Double, page: Int) async throws -> SearchResponse {
        searchQueries.append(query)
        return searchResponse
    }
    func suggestions() async throws -> SearchSuggestions { SearchSuggestions(suggestions: ["Latte"], categories: ["Coffee"]) }
}

final class FakeCartService: CartServicing {
    var result: PricedCart = Fixtures.pricedCart()
    private(set) var syncCalls = 0
    func sync(lines: [CartSyncRequest.Line], couponCode: String?) async throws -> PricedCart {
        syncCalls += 1
        return result
    }
    func reorder(orderId: String) async throws -> PricedCartResponse { throw APIError.offline }
}

final class FakeOrderService: OrderServicing {
    private(set) var placedKeys: [String] = []
    var orderToReturn = Fixtures.order()
    func placeOrder(addressId: String, paymentMethod: String, idempotencyKey: String) async throws -> PlaceOrderResponse {
        placedKeys.append(idempotencyKey)
        return PlaceOrderResponse(order: orderToReturn, payment: orderToReturn.payments.first, replayed: placedKeys.count > 1)
    }
    func orders(status: String, page: Int) async throws -> OrderListResponse { OrderListResponse(orders: [], meta: nil) }
    func activeOrders() async throws -> [OrderSummary] { [] }
    func order(id: String) async throws -> OrderDetail { orderToReturn }
    func tracking(id: String) async throws -> OrderTracking { throw APIError.offline }
    func cancel(id: String, reason: String?) async throws -> OrderDetail { orderToReturn }
}

final class FakePaymentService: PaymentServicing {
    func methods() async throws -> [PaymentMethodOption] {
        [PaymentMethodOption(id: "MOCK", title: "Demo", subtitle: "", isMock: true), PaymentMethodOption(id: "CASH_ON_DELIVERY", title: "Cash", subtitle: "", isMock: false)]
    }
    func completeMock(paymentId: String, outcome: String) async throws -> OrderDetail { Fixtures.order(status: outcome == "success" ? .placed : .pendingPayment) }
    func verifyRazorpay(paymentId: String, orderId: String, razorpayPaymentId: String, signature: String) async throws -> OrderDetail { Fixtures.order(status: .placed) }
    func reportFailure(paymentId: String, cancelled: Bool, reason: String?) async throws -> OrderDetail { Fixtures.order() }
    func newAttempt(orderId: String, method: String) async throws -> PaymentInfo { Fixtures.order().payments[0] }
}

final class FakeAddressService: AddressServicing {
    var addresses = [Fixtures.address]
    func list() async throws -> [Address] { addresses }
    func create(_ input: AddressInput) async throws -> Address { Fixtures.address }
    func update(id: String, _ input: AddressInput) async throws -> Address { Fixtures.address }
    func delete(id: String) async throws {}
}

/// API client that always fails — for SessionStore's refresh client in tests.
struct FailingClient: APIClient {
    func send<Response: Decodable>(_ endpoint: Endpoint<Response>) async throws -> Response { throw APIError.offline }
}

@MainActor
func makeSession(signedIn: Bool = true) -> SessionStore {
    let session = SessionStore(keychain: KeychainStore(service: "test.\(UUID().uuidString)"), refreshClient: FailingClient())
    if signedIn { session.signIn(user: Fixtures.user, tokens: Fixtures.tokens) }
    return session
}

@MainActor
func makeCart() -> CartStore { CartStore(stack: CoreDataStack(inMemory: true)) }
