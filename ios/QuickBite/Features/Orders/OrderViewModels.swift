import Foundation
import NetworkKit

@MainActor
final class OrdersViewModel {
    enum Filter: Int { case active, past }

    private let orders: OrderServicing
    private let cartService: CartServicing
    private let cart: CartStore
    let session: SessionStore
    private(set) var items: [OrderSummary] = []
    private(set) var isLoading = false
    private(set) var error: APIError?
    var filter: Filter = .active
    var onChange: (() -> Void)?

    init(orders: OrderServicing, cartService: CartServicing, cart: CartStore, session: SessionStore) {
        self.orders = orders
        self.cartService = cartService
        self.cart = cart
        self.session = session
    }

    convenience init(env: AppEnvironment) {
        self.init(orders: env.orders, cartService: env.cartService, cart: env.cart, session: env.session)
    }

    func load() {
        guard session.isSignedIn else {
            items = []
            onChange?()
            return
        }
        isLoading = true
        error = nil
        onChange?()
        Task {
            do {
                let response = try await orders.orders(status: filter == .active ? "active" : "past", page: 1)
                items = response.orders
            } catch {
                self.error = (error as? APIError) ?? .transport(error.localizedDescription)
            }
            isLoading = false
            onChange?()
        }
    }

    /// Puts a past order's available items back in the cart.
    /// Returns the names of items that couldn't be added.
    func reorder(_ order: OrderSummary) async throws -> [String] {
        let response = try await cartService.reorder(orderId: order.id)
        cart.replace(with: response.cart)
        return response.skippedItems ?? []
    }
}

/// Live tracking: initial snapshot over REST, then status + (demo) rider
/// position over the realtime socket. Falls back to polling if the socket
/// can't connect.
@MainActor
final class OrderTrackingViewModel {
    let orderId: String
    private let orders: OrderServicing
    private let realtime: RealtimeClient
    private let cartService: CartServicing
    private let cart: CartStore
    private var observer: UUID?
    private var pollTask: Task<Void, Never>?
    private var isSocketConnected = false

    private(set) var order: OrderDetail?
    private(set) var tracking: OrderTracking?
    private(set) var rider: RiderLocation?
    private(set) var error: APIError?
    var onChange: (() -> Void)?
    /// Fired when a status change arrives live (for a little celebration).
    var onLiveStatus: ((OrderStatus) -> Void)?

    init(orderId: String, orders: OrderServicing, realtime: RealtimeClient, cartService: CartServicing, cart: CartStore) {
        self.orderId = orderId
        self.orders = orders
        self.realtime = realtime
        self.cartService = cartService
        self.cart = cart
    }

    convenience init(orderId: String, env: AppEnvironment) {
        self.init(orderId: orderId, orders: env.orders, realtime: env.realtime, cartService: env.cartService, cart: env.cart)
    }

    var status: OrderStatus { tracking?.status ?? order?.status ?? .placed }
    var isLive: Bool { isSocketConnected }

    /// Minutes remaining based on the estimate and time since placing.
    var minutesRemaining: Int? {
        guard let order, status.isActive else { return nil }
        let elapsed = Int(Date().timeIntervalSince(order.createdAt) / 60)
        return max(1, order.estimatedMinutes - elapsed)
    }

    func start() {
        observer = realtime.observe { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        realtime.watch(orderId: orderId)
        Task { await refresh() }
        startPolling()
    }

    func stop() {
        if let observer { realtime.removeObserver(observer) }
        realtime.unwatch(orderId: orderId)
        pollTask?.cancel()
    }

    func refresh() async {
        do {
            order = try await orders.order(id: orderId)
            tracking = try await orders.tracking(id: orderId)
            rider = tracking?.rider ?? rider
            error = nil
        } catch {
            self.error = (error as? APIError) ?? .transport(error.localizedDescription)
        }
        onChange?()
        if status.isFinal { pollTask?.cancel() }
    }

    /// Safety net when realtime isn't available: poll every 10 s while active.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if !self.isSocketConnected && !self.status.isFinal { await self.refresh() }
            }
        }
    }

    private func handle(_ event: RealtimeClient.Event) {
        switch event {
        case let .orderStatus(id, newStatus, _) where id == orderId:
            let changed = newStatus != status
            Task {
                await refresh()
                if changed { onLiveStatus?(newStatus) }
            }
        case let .riderLocation(id, location) where id == orderId:
            rider = location
            onChange?()
        case .connectionChanged(let connected):
            isSocketConnected = connected
            onChange?()
        default:
            break
        }
    }

    func cancel(reason: String?) async throws {
        order = try await orders.cancel(id: orderId, reason: reason)
        await refresh()
    }

    func reorder() async throws -> [String] {
        let response = try await cartService.reorder(orderId: orderId)
        cart.replace(with: response.cart)
        return response.skippedItems ?? []
    }
}
