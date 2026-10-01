import Foundation
import NetworkKit

@MainActor
final class HomeViewModel {
    struct Content {
        var feed: HomeFeed
        var isFromCache: Bool
        var savedAt: Date?
    }

    enum State {
        case loading
        case loaded(Content)
        case failed(APIError)
    }

    private let catalog: CatalogServicing
    private let cache: ResponseCache
    private let locationStore: DeliveryLocationStore
    private let session: SessionStore
    private var loadTask: Task<Void, Never>?

    private(set) var state: State = .loading { didSet { onStateChange?(state) } }
    var onStateChange: ((State) -> Void)?

    init(catalog: CatalogServicing, cache: ResponseCache, locationStore: DeliveryLocationStore, session: SessionStore) {
        self.catalog = catalog
        self.cache = cache
        self.locationStore = locationStore
        self.session = session
    }

    convenience init(env: AppEnvironment) {
        self.init(catalog: env.catalog, cache: env.cache, locationStore: env.deliveryLocation, session: env.session)
    }

    var location: DeliveryLocationStore.Location { locationStore.current }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part: String
        switch hour {
        case 5..<12: part = "Good morning"
        case 12..<17: part = "Good afternoon"
        case 17..<22: part = "Good evening"
        default: part = "Late-night cravings"
        }
        if let name = session.user?.firstName { return "\(part), \(name)" }
        return part
    }

    private var cacheKey: String {
        // Round so tiny GPS jitter doesn't create new cache entries.
        String(format: "home_%.2f_%.2f", location.latitude, location.longitude)
    }

    /// Loads the feed. Shows cached content immediately (if any), then refreshes.
    func load(forceRefresh: Bool = false) {
        loadTask?.cancel()
        var hasContent = false
        if case .loaded = state { hasContent = true }
        if !hasContent, let cached = cache.load(HomeFeed.self, for: cacheKey) {
            state = .loaded(Content(feed: cached.value, isFromCache: true, savedAt: cached.savedAt))
        } else if !hasContent {
            state = .loading
        }
        loadTask = Task {
            do {
                let feed = try await catalog.home(lat: location.latitude, lng: location.longitude)
                guard !Task.isCancelled else { return }
                cache.store(feed, for: cacheKey)
                state = .loaded(Content(feed: feed, isFromCache: false, savedAt: Date()))
            } catch {
                guard !Task.isCancelled else { return }
                let apiError = (error as? APIError) ?? .transport(error.localizedDescription)
                if apiError == .cancelled { return }
                // Keep showing cached content (flagged as offline) when we have it.
                if let cached = cache.load(HomeFeed.self, for: cacheKey) {
                    state = .loaded(Content(feed: cached.value, isFromCache: true, savedAt: cached.savedAt))
                } else {
                    state = .failed(apiError)
                }
            }
        }
    }

    func offerHeadline(_ offer: Offer) -> String { CouponRules.headline(for: offer) }
}
