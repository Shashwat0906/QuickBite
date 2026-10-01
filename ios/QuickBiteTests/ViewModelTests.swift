import XCTest
import NetworkKit
@testable import QuickBite

final class AuthValidatorTests: XCTestCase {
    func testEmail() {
        XCTAssertNil(AuthValidator.email("asha@test.dev"))
        XCTAssertNotNil(AuthValidator.email("asha@"))
        XCTAssertEqual(AuthValidator.email(""), "Enter your email")
    }

    func testNewPasswordRules() {
        XCTAssertEqual(AuthValidator.password("short1", isNew: true), "Use at least 8 characters")
        XCTAssertEqual(AuthValidator.password("12345678", isNew: true), "Add at least one letter")
        XCTAssertEqual(AuthValidator.password("abcdefgh", isNew: true), "Add at least one number")
        XCTAssertNil(AuthValidator.password("Passw0rd!", isNew: true))
        XCTAssertNil(AuthValidator.password("anything", isNew: false), "login doesn't apply strength rules")
    }

    func testPhoneIsOptionalButValidated() {
        XCTAssertNil(AuthValidator.phone(""))
        XCTAssertNil(AuthValidator.phone("+91 98765 43210"))
        XCTAssertNotNil(AuthValidator.phone("12345"))
    }

    func testStrength() {
        XCTAssertEqual(AuthValidator.strength(""), 0)
        XCTAssertEqual(AuthValidator.strength("Passw0rd"), 2)
        XCTAssertEqual(AuthValidator.strength("Passw0rd!Long"), 4)
    }
}

@MainActor
final class LoginViewModelTests: XCTestCase {
    func testInvalidFormDoesNotCallAPI() async {
        let auth = FakeAuthService()
        let vm = LoginViewModel(auth: auth, isGoogleConfigured: false) { _, _ in }
        let errors = await vm.login(email: "bad", password: "")
        XCTAssertNotNil(errors.email)
        XCTAssertNotNil(errors.password)
        XCTAssertEqual(auth.loginCalls, 0)
        XCTAssertEqual(vm.state, .idle)
    }

    func testSuccessfulLoginPersistsSession() async {
        var persisted: User?
        let vm = LoginViewModel(auth: FakeAuthService(), isGoogleConfigured: false) { user, _ in persisted = user }
        var states: [LoginViewModel.State] = []
        vm.onStateChange = { states.append($0) }
        await vm.login(email: " Asha@Test.dev ", password: "Passw0rd!")
        XCTAssertEqual(persisted, Fixtures.user)
        XCTAssertEqual(states, [.loading, .signedIn])
    }

    func testServerErrorIsShown() async {
        let auth = FakeAuthService()
        auth.loginResult = .failure(APIError.unauthorized(message: "Incorrect email or password"))
        let vm = LoginViewModel(auth: auth, isGoogleConfigured: false) { _, _ in XCTFail("must not persist") }
        await vm.login(email: "a@b.co", password: "wrong")
        XCTAssertEqual(vm.state, .failed("Incorrect email or password"))
        vm.resetError()
        XCTAssertEqual(vm.state, .idle)
    }
}

@MainActor
final class SignupViewModelTests: XCTestCase {
    func testPasswordMismatch() async {
        let auth = FakeAuthService()
        let vm = SignupViewModel(auth: auth) { _, _ in }
        let errors = await vm.signUp(name: "Asha", email: "a@b.co", phone: "", password: "Passw0rd!", confirm: "Passw0rd?")
        XCTAssertEqual(errors.confirm, "Passwords don't match")
        XCTAssertEqual(auth.registerCalls, 0)
    }

    func testValidSignup() async {
        let auth = FakeAuthService()
        var signedIn = false
        let vm = SignupViewModel(auth: auth) { _, _ in signedIn = true }
        let errors = await vm.signUp(name: "Asha Verma", email: "a@b.co", phone: "+919876543210", password: "Passw0rd!", confirm: "Passw0rd!")
        XCTAssertTrue(errors.isValid)
        XCTAssertTrue(signedIn)
        XCTAssertEqual(vm.state, .signedIn)
    }
}

@MainActor
final class CheckoutViewModelTests: XCTestCase {
    private func makeVM(cart: CartStore, cartService: FakeCartService = FakeCartService(), orders: FakeOrderService = FakeOrderService()) -> CheckoutViewModel {
        CheckoutViewModel(cart: cart, cartService: cartService, addressService: FakeAddressService(), paymentService: FakePaymentService(),
                          orderService: orders, locationStore: DeliveryLocationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!), session: makeSession())
    }

    func testLoadSelectsDefaultAddressAndFirstMethod() async throws {
        let cart = makeCart()
        try cart.add(Fixtures.item(), from: CartCafe(Fixtures.cafe()), quantity: 2)
        let vm = makeVM(cart: cart)
        await vm.load()
        XCTAssertEqual(vm.selectedAddress, Fixtures.address)
        XCTAssertNotNil(vm.selectedMethodId)
        XCTAssertTrue(vm.canPlaceOrder)
        XCTAssertEqual(vm.bill?.totalPaise, 42190)
    }

    func testPlaceOrderReturnsMockStepAndClearsCart() async throws {
        let cart = makeCart()
        try cart.add(Fixtures.item(), from: CartCafe(Fixtures.cafe()), quantity: 2)
        let vm = makeVM(cart: cart)
        await vm.load()
        vm.select(methodId: "MOCK")
        let step = try await vm.placeOrder()
        guard case .mock(let payment, let order) = step else { return XCTFail("expected mock payment step") }
        XCTAssertEqual(payment.id, "p1")
        XCTAssertEqual(order.orderNumber, "QB-TEST1")
        XCTAssertTrue(cart.isEmpty, "server converted the cart into an order")
    }

    func testRetriesReuseTheSameIdempotencyKey() async throws {
        let cart = makeCart()
        try cart.add(Fixtures.item(), from: CartCafe(Fixtures.cafe()), quantity: 2)
        let orders = FakeOrderService()
        let vm = makeVM(cart: cart, orders: orders)
        await vm.load()
        _ = try await vm.placeOrder()
        try cart.add(Fixtures.item(), from: CartCafe(Fixtures.cafe()))
        _ = try await vm.placeOrder()
        XCTAssertEqual(orders.placedKeys.count, 2)
        XCTAssertEqual(Set(orders.placedKeys).count, 1)
    }

    func testCashOnDeliveryIsDoneImmediately() async throws {
        let cart = makeCart()
        try cart.add(Fixtures.item(), from: CartCafe(Fixtures.cafe()))
        let orders = FakeOrderService()
        orders.orderToReturn = Fixtures.order(status: .placed, provider: .cashOnDelivery)
        let vm = makeVM(cart: cart, orders: orders)
        await vm.load()
        guard case .done = try await vm.placeOrder() else { return XCTFail("expected done") }
    }

    func testBlockingIssuePreventsOrder() async throws {
        let cart = makeCart()
        try cart.add(Fixtures.item(), from: CartCafe(Fixtures.cafe()))
        let service = FakeCartService()
        service.result = Fixtures.pricedCart(canCheckout: false, issues: [CartIssue(code: "OUT_OF_STOCK", message: "Only 1 left", menuItemId: "i1")])
        let orders = FakeOrderService()
        let vm = makeVM(cart: cart, cartService: service, orders: orders)
        await vm.load()
        XCTAssertFalse(vm.canPlaceOrder)
        XCTAssertEqual(vm.blockingIssue, "Only 1 left")
        do {
            _ = try await vm.placeOrder()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual((error as? APIError)?.code, "CART_INVALID")
            XCTAssertTrue(orders.placedKeys.isEmpty)
        }
    }
}

@MainActor
final class SearchViewModelTests: XCTestCase {
    func testDebounceCollapsesKeystrokesIntoOneSearch() async throws {
        let catalog = FakeCatalogService()
        let vm = SearchViewModel(catalog: catalog, recentStore: RecentSearchesStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
                                 locationStore: DeliveryLocationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!), debounce: .milliseconds(80))
        let done = expectation(description: "results")
        vm.onStateChange = { state in if case .results = state { done.fulfill() } }
        for prefix in ["l", "la", "lat", "latt", "latte"] { vm.updateQuery(prefix) }
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(catalog.searchQueries, ["latte"])
    }

    func testSubmitStoresRecentSearch() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let recent = RecentSearchesStore(defaults: defaults)
        let vm = SearchViewModel(catalog: FakeCatalogService(), recentStore: recent, locationStore: DeliveryLocationStore(defaults: defaults))
        vm.submit("Cold brew")
        XCTAssertEqual(recent.terms.first, "Cold brew")
    }

    func testEmptyResults() async throws {
        let catalog = FakeCatalogService()
        catalog.searchResponse = SearchResponse(query: "zzz", cafes: [], items: [], meta: PageMeta(page: 1, limit: 20, total: 0, totalPages: 0, hasMore: false))
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let vm = SearchViewModel(catalog: catalog, recentStore: RecentSearchesStore(defaults: defaults), locationStore: DeliveryLocationStore(defaults: defaults))
        let done = expectation(description: "empty")
        vm.onStateChange = { if case .empty("zzz") = $0 { done.fulfill() } }
        vm.submit("zzz")
        await fulfillment(of: [done], timeout: 2)
    }
}

@MainActor
final class WriteReviewViewModelTests: XCTestCase {
    final class FakeReviews: ReviewServicing {
        var submitted: (Int, String?)?
        func submit(orderId: String, rating: Int, comment: String?) async throws -> Review {
            submitted = (rating, comment)
            return Review(id: "r1", orderId: orderId, cafeId: "c1", rating: rating, comment: comment, createdAt: Date(), userName: nil, cafeName: nil)
        }
        func cafeReviews(cafeId: String, page: Int) async throws -> ReviewListResponse { throw APIError.offline }
        func myReviews(page: Int) async throws -> ReviewListResponse { throw APIError.offline }
    }

    func testRatingRequired() async {
        let vm = WriteReviewViewModel(orderId: "o1", cafeName: "Brew", service: FakeReviews())
        XCTAssertNotNil(vm.validationMessage)
        do { _ = try await vm.submit(); XCTFail("expected validation error") } catch {}
    }

    func testSubmitTrimsComment() async throws {
        let service = FakeReviews()
        let vm = WriteReviewViewModel(orderId: "o1", cafeName: "Brew", service: service)
        vm.rating = 5
        vm.comment = "   "
        _ = try await vm.submit()
        XCTAssertEqual(service.submitted?.0, 5)
        XCTAssertNil(service.submitted?.1)
    }
}
