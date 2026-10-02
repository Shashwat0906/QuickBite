import UIKit
import NetworkKit

/// Dependency container. Built once at launch and passed down through the
/// coordinators, so nothing in the app reaches for globals/singletons and
/// every dependency can be swapped in tests.
@MainActor
final class AppEnvironment {
    let config: AppConfiguration
    let session: SessionStore
    let apiClient: URLSessionAPIClient

    let auth: AuthServicing
    let catalog: CatalogServicing
    let cartService: CartServicing
    let orders: OrderServicing
    let payments: PaymentServicing
    let addresses: AddressServicing
    let reviews: ReviewServicing
    let notifications: NotificationServicing
    let health: HealthService

    let cart: CartStore
    let cache: ResponseCache
    let recentSearches: RecentSearchesStore
    let deliveryLocation: DeliveryLocationStore
    let location: LocationService
    let realtime: RealtimeClient
    let push: PushNotificationManager
    let defaults: UserDefaults

    init(config: AppConfiguration) {
        self.config = config
        let defaults = UserDefaults.standard
        if config.resetState, let bundleId = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleId)
        }
        self.defaults = defaults

        // Transport: real URLSession, or the in-process stub server for UI tests.
        let transport: HTTPTransport
        #if DEBUG
        if config.isUITesting {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            transport = URLSession(configuration: configuration)
        } else {
            transport = URLSession(configuration: .default)
        }
        #else
        transport = URLSession(configuration: .default)
        #endif

        #if DEBUG
        let logging = !config.isUITesting
        #else
        let logging = false
        #endif

        // 30 s × (1 + 2 retries) comfortably covers a free-tier Render instance waking up (~50 s).
        let apiConfig = APIClientConfiguration(baseURL: config.apiV1URL, defaultTimeout: 30, logging: logging, defaultHeaders: ["X-Client": "QuickBite-iOS"])
        let refreshClient = URLSessionAPIClient(configuration: apiConfig, transport: transport)
        let keychain = KeychainStore(service: "com.quickbite.session", inMemory: config.isUITesting)
        if config.resetState { keychain.remove("tokens"); keychain.remove("user") }
        let session = SessionStore(keychain: keychain, refreshClient: refreshClient)
        self.session = session
        let client = URLSessionAPIClient(configuration: apiConfig, transport: transport, tokenProvider: session)
        self.apiClient = client

        auth = AuthService(client: client)
        catalog = CatalogService(client: client)
        cartService = CartService(client: client)
        orders = OrderService(client: client)
        payments = PaymentService(client: client)
        addresses = AddressService(client: client)
        reviews = ReviewService(client: client)
        let notifications = NotificationService(client: client)
        self.notifications = notifications
        health = HealthService(rootClient: URLSessionAPIClient(configuration: APIClientConfiguration(baseURL: config.apiBaseURL, maxRetries: 0), transport: transport))

        let stack = CoreDataStack(inMemory: config.isUITesting)
        cart = CartStore(stack: stack)
        if config.resetState { cart.clear() }
        cache = ResponseCache(folder: config.isUITesting ? "UITestCache" : "ResponseCache")
        if config.resetState { cache.removeAll() }
        recentSearches = RecentSearchesStore(defaults: defaults)
        deliveryLocation = DeliveryLocationStore(defaults: defaults)
        location = LocationService()
        realtime = RealtimeClient(baseURL: config.apiBaseURL, tokenProvider: session)
        push = PushNotificationManager(notificationService: notifications, session: session)
    }

    // MARK: Onboarding flag

    var hasSeenOnboarding: Bool {
        get { config.skipOnboarding || defaults.bool(forKey: "qb.hasSeenOnboarding") }
        set { defaults.set(newValue, forKey: "qb.hasSeenOnboarding") }
    }

    /// Signs out locally and on the server (revokes the refresh token, detaches the device).
    func signOut() async {
        let refresh = session.refreshToken
        let device = push.fcmToken
        session.signOut()
        realtime.disconnect()
        await auth.logout(refreshToken: refresh, deviceToken: device)
    }
}
