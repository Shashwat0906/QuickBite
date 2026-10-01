import Foundation
import NetworkKit

@MainActor
final class CafeDetailViewModel {
    enum State {
        case loading
        case loaded(Cafe, [MenuSection])
        case failed(APIError)
    }

    /// What the UI must do after a quantity tap.
    enum AddResult {
        case added
        case needsCustomization(MenuItem)
        case conflict(currentCafe: String, retry: () -> Void)
        case unavailable
    }

    let cafeId: String
    private let catalog: CatalogServicing
    private let cart: CartStore
    private let cache: ResponseCache
    private let locationStore: DeliveryLocationStore

    private(set) var state: State = .loading { didSet { onStateChange?(state) } }
    var onStateChange: ((State) -> Void)?
    var vegOnly = false

    init(cafeId: String, catalog: CatalogServicing, cart: CartStore, cache: ResponseCache, locationStore: DeliveryLocationStore) {
        self.cafeId = cafeId
        self.catalog = catalog
        self.cart = cart
        self.cache = cache
        self.locationStore = locationStore
    }

    convenience init(cafeId: String, env: AppEnvironment) {
        self.init(cafeId: cafeId, catalog: env.catalog, cart: env.cart, cache: env.cache, locationStore: env.deliveryLocation)
    }

    var cafe: Cafe? {
        if case .loaded(let cafe, _) = state { return cafe }
        return nil
    }

    /// Sections after the veg filter; empty sections are dropped.
    var visibleSections: [MenuSection] {
        guard case .loaded(_, let menu) = state else { return [] }
        guard vegOnly else { return menu }
        return menu.compactMap { section in
            let items = section.items.filter { $0.diet == .veg }
            return items.isEmpty ? nil : MenuSection(id: section.id, name: section.name, items: items)
        }
    }

    func load() {
        let key = "cafe_\(cafeId)"
        if case .loaded = state {} else if let cached = cache.load(CafeDetailResponse.self, for: key) {
            state = .loaded(cached.value.cafe, cached.value.menu)
        }
        Task {
            do {
                let location = locationStore.current
                let detail = try await catalog.cafeDetail(id: cafeId, lat: location.latitude, lng: location.longitude)
                cache.store(detail, for: key)
                state = .loaded(detail.cafe, detail.menu)
            } catch {
                if case .loaded = state { return } // keep cached menu
                state = .failed((error as? APIError) ?? .transport(error.localizedDescription))
            }
        }
    }

    func quantity(of item: MenuItem) -> Int { cart.quantity(of: item.id) }

    /// Called by the ADD / + / − control on a menu row.
    func setQuantity(_ newValue: Int, for item: MenuItem) -> AddResult {
        guard let cafe else { return .unavailable }
        guard item.isAvailable else { return .unavailable }
        let current = cart.quantity(of: item.id)
        // First add of a customisable item opens the customisation sheet.
        if item.isCustomizable && current == 0 && newValue > 0 { return .needsCustomization(item) }
        do {
            try cart.changeQuantity(of: item, from: CartCafe(cafe), to: newValue)
            return .added
        } catch CartError.differentCafe(let name) {
            return .conflict(currentCafe: name) { [weak self] in
                guard let self else { return }
                if item.isCustomizable { return }
                try? self.cart.add(item, from: CartCafe(cafe), quantity: max(1, newValue), replacingOtherCafe: true)
            }
        } catch {
            return .unavailable
        }
    }

    /// Adds an item configured in the customisation sheet.
    func addConfigured(_ item: MenuItem, from cafe: Cafe, optionIds: [String], quantity: Int, replacingOtherCafe: Bool) throws {
        try cart.add(item, from: CartCafe(cafe), optionIds: optionIds, quantity: quantity, replacingOtherCafe: replacingOtherCafe)
    }

    var cartSummary: (count: Int, total: Paise) { (cart.itemCount, cart.estimate.subtotalPaise) }
}

/// Customisation sheet logic: required groups, max selections, live price.
@MainActor
final class ItemCustomizationViewModel {
    let item: MenuItem
    private(set) var selected: Set<String>
    private(set) var quantity: Int

    init(item: MenuItem, preselected: [String]? = nil, quantity: Int = 1) {
        self.item = item
        self.quantity = quantity
        if let preselected {
            selected = Set(preselected)
        } else {
            // Default: first available option of every required single-choice group.
            selected = Set(item.customizations.compactMap { group in
                group.isRequired && group.isSingleChoice ? group.options.first(where: \.isAvailable)?.id : nil
            })
        }
    }

    func isSelected(_ option: CustomizationOption) -> Bool { selected.contains(option.id) }

    /// Toggles an option, respecting single-choice and max-select rules.
    /// Returns a message when the tap was rejected.
    @discardableResult
    func toggle(_ option: CustomizationOption, in group: CustomizationGroup) -> String? {
        guard option.isAvailable else { return "\(option.name) is unavailable" }
        if group.isSingleChoice {
            group.options.forEach { selected.remove($0.id) }
            selected.insert(option.id)
            return nil
        }
        if selected.contains(option.id) {
            selected.remove(option.id)
            return nil
        }
        let countInGroup = group.options.filter { selected.contains($0.id) }.count
        guard countInGroup < group.maxSelect else { return "You can choose up to \(group.maxSelect) \(group.name.lowercased())" }
        selected.insert(option.id)
        return nil
    }

    func setQuantity(_ value: Int) { quantity = max(1, min(CartStore.maxQuantityPerLine, value)) }

    /// First unmet requirement, if any.
    var validationMessage: String? {
        for group in item.customizations {
            let count = group.options.filter { selected.contains($0.id) }.count
            if count < group.minSelect { return "Please choose \(group.name.lowercased())" }
        }
        return nil
    }

    var unitPrice: Paise {
        let extras = item.customizations.flatMap(\.options).filter { selected.contains($0.id) }.map(\.extraPricePaise)
        return PricingCalculator.unitPrice(base: item.pricePaise, optionExtras: extras)
    }

    var totalPrice: Paise { unitPrice * quantity }
    var selectedIds: [String] { selected.sorted() }
}

@MainActor
final class CafeListViewModel {
    let title: String
    let category: String?
    private let catalog: CatalogServicing
    private let locationStore: DeliveryLocationStore
    private(set) var cafes: [Cafe] = []
    private(set) var isLoading = false
    private var page = 1
    private var hasMore = true
    var sort = "distance"
    var openNow = false
    var minRating: Double?
    var onChange: ((Result<[Cafe], APIError>) -> Void)?

    init(title: String, category: String?, catalog: CatalogServicing, locationStore: DeliveryLocationStore) {
        self.title = title
        self.category = category
        self.catalog = catalog
        self.locationStore = locationStore
    }

    convenience init(title: String, category: String?, env: AppEnvironment) {
        self.init(title: title, category: category, catalog: env.catalog, locationStore: env.deliveryLocation)
    }

    func reload() {
        page = 1
        hasMore = true
        cafes = []
        loadNextPage()
    }

    func loadNextPage() {
        guard !isLoading, hasMore else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let location = locationStore.current
                let response = try await catalog.cafes(lat: location.latitude, lng: location.longitude, category: category, minRating: minRating, openNow: openNow, sort: sort, page: page)
                cafes += response.cafes
                hasMore = response.meta.hasMore
                page += 1
                onChange?(.success(cafes))
            } catch {
                onChange?(.failure((error as? APIError) ?? .transport(error.localizedDescription)))
            }
        }
    }
}
