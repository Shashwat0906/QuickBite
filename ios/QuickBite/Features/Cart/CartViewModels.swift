import Foundation
import NetworkKit

/// Cart screen state. Guests see a local estimate; signed-in users get the
/// server's authoritative prices, coupon result and stock/price issues.
@MainActor
final class CartViewModel {
    struct Display {
        var lines: [CartLine]
        var bill: Bill
        var isEstimate: Bool
        var coupon: CouponResult?
        var couponCode: String?
        var issues: [CartIssue]
        var cafeName: String?
        var canCheckout: Bool
        var isSyncing: Bool
        var freeDeliveryHint: String?
    }

    private let cart: CartStore
    private let cartService: CartServicing
    private let session: SessionStore
    private var serverCart: PricedCart?
    private var syncTask: Task<Void, Never>?
    private var isSyncing = false
    private var syncError: String?

    var onChange: ((Display) -> Void)?

    init(cart: CartStore, cartService: CartServicing, session: SessionStore) {
        self.cart = cart
        self.cartService = cartService
        self.session = session
    }

    convenience init(env: AppEnvironment) {
        self.init(cart: env.cart, cartService: env.cartService, session: env.session)
    }

    var isSignedIn: Bool { session.isSignedIn }
    var isEmpty: Bool { cart.isEmpty }

    var display: Display {
        let useServer = serverCart != nil && !isSyncing
        let bill = (useServer ? serverCart?.bill : nil) ?? cart.estimate
        var issues = serverCart?.issues ?? []
        if let syncError { issues.append(CartIssue(code: "SYNC_FAILED", message: syncError, menuItemId: nil)) }
        let hint = PricingCalculator.amountToFreeDelivery(subtotal: bill.subtotalPaise).map { "Add \(Money.format($0)) more for FREE delivery" }
        return Display(
            lines: cart.lines,
            bill: bill,
            isEstimate: !useServer,
            coupon: serverCart?.coupon,
            couponCode: cart.couponCode,
            issues: issues,
            cafeName: cart.cafe?.name,
            canCheckout: !cart.isEmpty && (serverCart?.canCheckout ?? true) && !isSyncing,
            isSyncing: isSyncing,
            freeDeliveryHint: cart.isEmpty ? nil : hint
        )
    }

    func refresh() {
        publish()
        scheduleSync(delayMilliseconds: 0)
    }

    func setQuantity(_ quantity: Int, for line: CartLine) {
        cart.setQuantity(quantity, forLine: line.id)
        afterMutation()
    }

    func remove(_ line: CartLine) {
        cart.remove(line: line.id)
        afterMutation()
    }

    func updateOptions(_ optionIds: [String], quantity: Int, for line: CartLine) {
        cart.updateOptions(optionIds, forLine: line.id)
        if let updated = cart.lines.first(where: { $0.mergeKey == CartLine(id: line.id, menuItem: line.menuItem, optionIds: optionIds.sorted(), quantity: quantity).mergeKey }) {
            cart.setQuantity(quantity, forLine: updated.id)
        }
        afterMutation()
    }

    func applyCoupon(_ code: String?) {
        cart.applyCoupon(code)
        afterMutation(immediate: true)
    }

    func clear() {
        cart.clear()
        serverCart = nil
        publish()
    }

    /// Server issue for a line (e.g. "Only 2 left"), matched by menu item.
    func issue(for line: CartLine) -> CartIssue? {
        serverCart?.lines.first { $0.menuItem.id == line.menuItem.id && Set($0.optionIds) == Set(line.optionIds) }?.issue
    }

    private func afterMutation(immediate: Bool = false) {
        publish()
        scheduleSync(delayMilliseconds: immediate ? 0 : 400)
    }

    /// Debounced server sync so rapid +/+/+ taps send one request.
    private func scheduleSync(delayMilliseconds: UInt64) {
        syncTask?.cancel()
        guard session.isSignedIn, !cart.isEmpty else {
            serverCart = nil
            syncError = nil
            publish()
            return
        }
        syncTask = Task {
            if delayMilliseconds > 0 { try? await Task.sleep(nanoseconds: delayMilliseconds * 1_000_000) }
            guard !Task.isCancelled else { return }
            isSyncing = true
            publish()
            do {
                let priced = try await cartService.sync(lines: cart.syncLines, couponCode: cart.couponCode)
                guard !Task.isCancelled else { return }
                serverCart = priced
                syncError = nil
            } catch {
                guard !Task.isCancelled else { return }
                serverCart = nil
                let apiError = error as? APIError
                syncError = apiError == .offline ? "You're offline — prices shown are estimates." : (apiError?.userMessage ?? error.localizedDescription)
            }
            isSyncing = false
            publish()
        }
    }

    private func publish() { onChange?(display) }
}

/// Checkout: address + payment method + server-priced bill → order → payment.
@MainActor
final class CheckoutViewModel {
    enum PaymentStep {
        case mock(PaymentInfo, OrderDetail)
        case razorpay(PaymentInfo, OrderDetail)
        case done(OrderDetail)
    }

    private let cart: CartStore
    private let cartService: CartServicing
    private let addressService: AddressServicing
    private let paymentService: PaymentServicing
    private let orderService: OrderServicing
    private let locationStore: DeliveryLocationStore
    let session: SessionStore

    private(set) var addresses: [Address] = []
    private(set) var methods: [PaymentMethodOption] = []
    private(set) var pricedCart: PricedCart?
    private(set) var isLoading = false
    private(set) var isPlacing = false
    private(set) var loadError: String?
    var selectedAddress: Address?
    var selectedMethodId: String?
    /// One key per checkout attempt: retries / double taps can't create a second order.
    private(set) var idempotencyKey = UUID().uuidString
    private(set) var pendingOrder: OrderDetail?

    var onChange: (() -> Void)?

    init(cart: CartStore, cartService: CartServicing, addressService: AddressServicing, paymentService: PaymentServicing, orderService: OrderServicing, locationStore: DeliveryLocationStore, session: SessionStore) {
        self.cart = cart
        self.cartService = cartService
        self.addressService = addressService
        self.paymentService = paymentService
        self.orderService = orderService
        self.locationStore = locationStore
        self.session = session
    }

    convenience init(env: AppEnvironment) {
        self.init(cart: env.cart, cartService: env.cartService, addressService: env.addresses, paymentService: env.payments, orderService: env.orders, locationStore: env.deliveryLocation, session: env.session)
    }

    var bill: Bill? { pricedCart?.bill }
    var blockingIssue: String? {
        if let issue = pricedCart?.issues.first { return issue.message }
        if pricedCart?.coupon?.isValid == false { return pricedCart?.coupon?.message }
        return nil
    }

    var canPlaceOrder: Bool {
        selectedAddress != nil && selectedMethodId != nil && (pricedCart?.canCheckout ?? false) && blockingIssue == nil && !isPlacing
    }

    var placeButtonTitle: String {
        guard let total = bill?.totalPaise else { return "Place order" }
        return selectedMethodId == "CASH_ON_DELIVERY" ? "Place order · \(Money.format(total))" : "Pay \(Money.format(total))"
    }

    func load() async {
        isLoading = true
        loadError = nil
        onChange?()
        do {
            // Three independent requests run in parallel. (Unstructured tasks over
            // values captured on the main actor, instead of `async let` inside this
            // @MainActor type — that combination crashed the Swift runtime in CI.)
            let addressService = self.addressService
            let paymentService = self.paymentService
            let cartService = self.cartService
            let lines = cart.syncLines
            let coupon = cart.couponCode
            let addressesTask = Task { try await addressService.list() }
            let methodsTask = Task { try await paymentService.methods() }
            let pricedTask = Task { try await cartService.sync(lines: lines, couponCode: coupon) }
            addresses = try await addressesTask.value
            methods = try await methodsTask.value
            pricedCart = try await pricedTask.value
            let preferred = locationStore.current.addressId
            selectedAddress = addresses.first { $0.id == preferred } ?? addresses.first { $0.isDefault } ?? addresses.first
            let savedMethod = UserDefaults.standard.string(forKey: PaymentPreferences.defaultsKey)
            selectedMethodId = methods.first { $0.id == savedMethod }?.id ?? methods.first?.id
        } catch {
            loadError = (error as? APIError)?.userMessage ?? error.localizedDescription
        }
        isLoading = false
        onChange?()
    }

    func select(address: Address) {
        if !addresses.contains(address) { addresses.insert(address, at: 0) }
        selectedAddress = address
        onChange?()
    }

    func select(methodId: String) {
        selectedMethodId = methodId
        onChange?()
    }

    /// Creates the order (idempotent) and says which payment UI comes next.
    func placeOrder() async throws -> PaymentStep {
        guard let address = selectedAddress, let method = selectedMethodId else {
            throw APIError.server(status: 400, code: "INCOMPLETE", message: "Choose an address and a payment method")
        }
        guard !isPlacing else { throw APIError.server(status: 409, code: "IN_PROGRESS", message: "Your order is already being placed") }
        isPlacing = true
        onChange?()
        defer { isPlacing = false; onChange?() }

        // Make sure the server cart matches what the user sees right now.
        pricedCart = try await cartService.sync(lines: cart.syncLines, couponCode: cart.couponCode)
        if let issue = blockingIssue { throw APIError.server(status: 422, code: "CART_INVALID", message: issue) }

        let response = try await orderService.placeOrder(addressId: address.id, paymentMethod: method, idempotencyKey: idempotencyKey)
        pendingOrder = response.order
        // The server has turned the cart into an order; clear the local copy.
        cart.clear()
        return step(for: response.order, payment: response.payment)
    }

    private func step(for order: OrderDetail, payment: PaymentInfo?) -> PaymentStep {
        guard order.status == .pendingPayment, let payment else { return .done(order) }
        switch payment.provider {
        case .mock: return .mock(payment, order)
        case .razorpay: return .razorpay(payment, order)
        case .cashOnDelivery: return .done(order)
        }
    }

    func completeMockPayment(_ payment: PaymentInfo, outcome: String) async throws -> OrderDetail {
        try await paymentService.completeMock(paymentId: payment.id, outcome: outcome)
    }

    func verifyRazorpay(_ payment: PaymentInfo, paymentId: String, orderId: String, signature: String) async throws -> OrderDetail {
        try await paymentService.verifyRazorpay(paymentId: payment.id, orderId: orderId, razorpayPaymentId: paymentId, signature: signature)
    }

    func reportPaymentFailure(_ payment: PaymentInfo, cancelled: Bool, reason: String?) async {
        _ = try? await paymentService.reportFailure(paymentId: payment.id, cancelled: cancelled, reason: reason)
    }

    /// After a failed/cancelled payment: start a fresh attempt for the same order.
    func retryPayment(order: OrderDetail) async throws -> PaymentStep {
        let method = order.paymentMethod == .razorpay ? "RAZORPAY" : "MOCK"
        let payment = try await paymentService.newAttempt(orderId: order.id, method: method)
        return step(for: order, payment: payment)
    }

    func cancelUnpaidOrder(_ order: OrderDetail) async {
        _ = try? await orderService.cancel(id: order.id, reason: "Payment not completed")
    }
}

enum PaymentPreferences {
    static let defaultsKey = "qb.preferredPaymentMethod"
}
