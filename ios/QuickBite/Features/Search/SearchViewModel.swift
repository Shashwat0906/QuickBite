import Combine
import Foundation
import NetworkKit

/// Search with a 300 ms debounce (Combine is used here because debouncing a
/// stream of keystrokes is exactly what it's good at), plus filters, sorting,
/// pagination, and recent / suggested searches.
@MainActor
final class SearchViewModel {
    enum State: Equatable {
        case idle(recent: [String], suggestions: [String], categories: [String])
        case loading
        case results(cafes: [Cafe], items: [MenuItem], hasMore: Bool)
        case empty(query: String)
        case failed(String)
    }

    private let catalog: CatalogServicing
    private let recentStore: RecentSearchesStore
    private let locationStore: DeliveryLocationStore
    private let debounce: DispatchQueue.SchedulerTimeType.Stride
    private let querySubject = PassthroughSubject<String, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var page = 1
    private var suggestions: [String] = []
    private var categories: [String] = []

    private(set) var query = ""
    var filters = SearchFilters() { didSet { if filters != oldValue { runSearch(reset: true) } } }
    private(set) var state: State { didSet { onStateChange?(state) } }
    var onStateChange: ((State) -> Void)?

    init(catalog: CatalogServicing, recentStore: RecentSearchesStore, locationStore: DeliveryLocationStore, debounce: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(300)) {
        self.catalog = catalog
        self.recentStore = recentStore
        self.locationStore = locationStore
        self.debounce = debounce
        self.state = .idle(recent: recentStore.terms, suggestions: [], categories: [])
        querySubject
            .removeDuplicates()
            .debounce(for: debounce, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.runSearch(reset: true) }
            }
            .store(in: &cancellables)
    }

    convenience init(env: AppEnvironment) {
        self.init(catalog: env.catalog, recentStore: env.recentSearches, locationStore: env.deliveryLocation)
    }

    func loadSuggestions() {
        Task {
            if let result = try? await catalog.suggestions() {
                suggestions = result.suggestions
                categories = result.categories
                if case .idle = state { showIdle() }
            }
        }
    }

    /// Called on every keystroke; the search runs once typing pauses.
    func updateQuery(_ text: String) {
        query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty && filters.isDefault {
            searchTask?.cancel()
            showIdle()
        }
        querySubject.send(query)
    }

    /// Search immediately (return key, tapping a suggestion).
    func submit(_ text: String) {
        query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        recentStore.add(query)
        runSearch(reset: true)
    }

    func clearRecent() {
        recentStore.clear()
        showIdle()
    }

    func loadMore() {
        guard case .results(_, _, true) = state else { return }
        runSearch(reset: false)
    }

    private func showIdle() {
        state = .idle(recent: recentStore.terms, suggestions: suggestions, categories: categories)
    }

    private func runSearch(reset: Bool) {
        guard !query.isEmpty || !filters.isDefault else { showIdle(); return }
        searchTask?.cancel()
        if reset {
            page = 1
            state = .loading
        }
        let currentQuery = query
        let currentFilters = filters
        let location = locationStore.current
        let requestedPage = page
        searchTask = Task {
            do {
                let response = try await catalog.search(query: currentQuery, filters: currentFilters, lat: location.latitude, lng: location.longitude, page: requestedPage)
                guard !Task.isCancelled else { return }
                var cafes = response.cafes
                var items = response.items
                if !reset, case .results(let oldCafes, let oldItems, _) = state {
                    cafes = oldCafes
                    items = (oldItems + items).uniqued()
                }
                page = requestedPage + 1
                if cafes.isEmpty && items.isEmpty {
                    state = .empty(query: currentQuery)
                } else {
                    state = .results(cafes: cafes, items: items, hasMore: response.meta.hasMore)
                }
            } catch {
                guard !Task.isCancelled, (error as? APIError) != .cancelled else { return }
                state = .failed((error as? APIError)?.userMessage ?? error.localizedDescription)
            }
        }
    }
}
