import UIKit
import DesignKit
import NetworkKit

/// Home tab: greeting + location, search, offers carousel, categories,
/// featured cafes, popular dishes and nearby cafes.
final class HomeViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    private enum Section: Int, CaseIterable {
        case header, offers, categories, featured, dishes, nearby
        var title: String? {
            switch self {
            case .featured: return "Featured cafés"
            case .dishes: return "Popular right now"
            case .nearby: return "All cafés near you"
            case .categories: return "What are you craving?"
            default: return nil
            }
        }
    }

    private enum Item: Hashable {
        case header
        case offer(Offer)
        case category(String)
        case featured(Cafe)
        case dish(MenuItem)
        case nearby(Cafe)
    }

    private let viewModel: HomeViewModel
    private weak var router: AppRouting?
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let skeleton = SkeletonListView(rows: 5, imageSize: 96)
    private let offlineBanner = OfflineBanner()
    private var content: HomeViewModel.Content?
    private var observers: [NSObjectProtocol] = []

    init(viewModel: HomeViewModel, router: AppRouting) {
        self.viewModel = viewModel
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DK.Color.background
        navigationItem.title = ""
        navigationController?.setNavigationBarHidden(true, animated: false)
        configureCollectionView()
        configureDataSource()

        view.addSubview(offlineBanner)
        offlineBanner.isHidden = true
        NSLayoutConstraint.activate([
            offlineBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            offlineBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            offlineBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        viewModel.onStateChange = { [weak self] state in self?.render(state) }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .deliveryLocationDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.viewModel.load(forceRefresh: true) }
        })
        observers.append(center.addObserver(forName: .sessionDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadHeader() }
        })
        render(.loading)
        viewModel.load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: Layout

    private func configureCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = DK.Color.background
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.accessibilityIdentifier = "homeCollection"
        collectionView.register(HomeHeaderCell.self, forCellWithReuseIdentifier: HomeHeaderCell.reuseID)
        collectionView.register(OfferCell.self, forCellWithReuseIdentifier: OfferCell.reuseID)
        collectionView.register(CategoryCell.self, forCellWithReuseIdentifier: CategoryCell.reuseID)
        collectionView.register(CafeCardCell.self, forCellWithReuseIdentifier: CafeCardCell.reuseID)
        collectionView.register(DishTileCell.self, forCellWithReuseIdentifier: DishTileCell.reuseID)
        collectionView.register(SectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: SectionHeaderView.reuseID)
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self] _ in self?.viewModel.load(forceRefresh: true) }, for: .valueChanged)
        collectionView.refreshControl = refresh
        view.addSubview(collectionView)
        collectionView.pinEdges(to: view)
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let section = self?.dataSource?.snapshot().sectionIdentifiers[safe: index] else { return nil }
            let page = DK.Spacing.page
            let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44)),
                                                                      elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
            let layoutSection: NSCollectionLayoutSection
            switch section {
            case .header:
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(160)))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(160)), subitems: [item])
                layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.contentInsets = .init(top: DK.Spacing.s, leading: page, bottom: DK.Spacing.l, trailing: page)
                return layoutSection
            case .offers:
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(0.86), heightDimension: .absolute(132)), subitems: [item])
                layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.orthogonalScrollingBehavior = .groupPagingCentered
                layoutSection.interGroupSpacing = DK.Spacing.m
                layoutSection.contentInsets = .init(top: 0, leading: 0, bottom: DK.Spacing.xl, trailing: 0)
                return layoutSection
            case .categories:
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(84), heightDimension: .absolute(98)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(84), heightDimension: .absolute(98)), subitems: [item])
                layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.orthogonalScrollingBehavior = .continuous
                layoutSection.interGroupSpacing = DK.Spacing.s
            case .featured:
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(min(300, environment.container.contentSize.width * 0.78)), heightDimension: .absolute(250)), subitems: [item])
                layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
                layoutSection.interGroupSpacing = DK.Spacing.m
            case .dishes:
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(140), heightDimension: .absolute(210)), subitems: [item])
                layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.orthogonalScrollingBehavior = .continuous
                layoutSection.interGroupSpacing = DK.Spacing.m
            case .nearby:
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(270)))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(270)), subitems: [item])
                layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = DK.Spacing.l
            }
            layoutSection.boundarySupplementaryItems = [header]
            layoutSection.contentInsets = .init(top: DK.Spacing.xs, leading: page, bottom: DK.Spacing.xxl, trailing: page)
            return layoutSection
        }
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            guard let self else { return nil }
            switch item {
            case .header:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: HomeHeaderCell.reuseID, for: indexPath) as! HomeHeaderCell
                let location = self.viewModel.location
                cell.configure(greeting: self.viewModel.greeting, locationTitle: location.title, locationSubtitle: location.subtitle,
                               etaMinutes: self.content?.feed.fastestDeliveryMinutes)
                cell.onLocationTap = { [weak self] in self?.router?.showLocationPicker() }
                cell.onSearchTap = { [weak self] in self?.router?.showSearch(query: nil) }
                return cell
            case .offer(let offer):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: OfferCell.reuseID, for: indexPath) as! OfferCell
                cell.configure(headline: self.viewModel.offerHeadline(offer), description: offer.description, code: offer.code, index: indexPath.item)
                return cell
            case .category(let name):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CategoryCell.reuseID, for: indexPath) as! CategoryCell
                cell.configure(name: name)
                return cell
            case .featured(let cafe), .nearby(let cafe):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CafeCardCell.reuseID, for: indexPath) as! CafeCardCell
                cell.configure(CafeCardModel.from(cafe))
                return cell
            case .dish(let dish):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DishTileCell.reuseID, for: indexPath) as! DishTileCell
                cell.configure(FoodItemCardModel.from(dish, quantity: 0))
                return cell
            }
        }
        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: SectionHeaderView.reuseID, for: indexPath) as! SectionHeaderView
            let section = self?.dataSource.snapshot().sectionIdentifiers[safe: indexPath.section]
            let subtitle: String? = section == .nearby ? "Sorted by distance" : nil
            header.configure(title: section?.title ?? "", subtitle: subtitle, action: section == .featured ? "See all" : nil)
            header.onAction = { [weak self] in self?.router?.showCafeList(title: "All cafés", category: nil) }
            return header
        }
    }

    // MARK: Rendering

    private func render(_ state: HomeViewModel.State) {
        switch state {
        case .loading:
            installOverlay(skeleton)
        case .loaded(let content):
            self.content = content
            installOverlay(nil)
            collectionView.refreshControl?.endRefreshing()
            offlineBanner.isHidden = !content.isFromCache || NetworkMonitor.shared.isOnline
            apply(content.feed)
        case .failed(let error):
            collectionView.refreshControl?.endRefreshing()
            installOverlay(makeStateView(for: error) { [weak self] in self?.viewModel.load(forceRefresh: true) })
        }
    }

    private func apply(_ feed: HomeFeed) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.header])
        snapshot.appendItems([.header], toSection: .header)
        if !feed.offers.isEmpty {
            snapshot.appendSections([.offers])
            snapshot.appendItems(feed.offers.map(Item.offer), toSection: .offers)
        }
        if !feed.categories.isEmpty {
            snapshot.appendSections([.categories])
            snapshot.appendItems(feed.categories.map(Item.category), toSection: .categories)
        }
        if !feed.featuredCafes.isEmpty {
            snapshot.appendSections([.featured])
            snapshot.appendItems(feed.featuredCafes.map(Item.featured), toSection: .featured)
        }
        if !feed.popularDishes.isEmpty {
            snapshot.appendSections([.dishes])
            snapshot.appendItems(feed.popularDishes.map(Item.dish), toSection: .dishes)
        }
        if !feed.nearbyCafes.isEmpty {
            snapshot.appendSections([.nearby])
            snapshot.appendItems(feed.nearbyCafes.map(Item.nearby), toSection: .nearby)
        }
        snapshot.reconfigureItems([.header])
        dataSource.apply(snapshot, animatingDifferences: false)
        if feed.nearbyCafes.isEmpty {
            let empty = StateView(.empty(symbol: "mappin.slash", title: "No cafés deliver here yet", message: "Try another address — we're expanding quickly."),
                                  actionTitle: "Change location") { [weak self] in self?.router?.showLocationPicker() }
            installOverlay(empty)
        }
    }

    private func reloadHeader() {
        var snapshot = dataSource.snapshot()
        guard snapshot.itemIdentifiers.contains(.header) else { return }
        snapshot.reconfigureItems([.header])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .featured(let cafe), .nearby(let cafe):
            router?.showCafe(id: cafe.id)
        case .dish(let dish):
            router?.showCafe(id: dish.cafeId)
        case .category(let name):
            router?.showCafeList(title: name, category: name)
        case .offer(let offer):
            UIPasteboard.general.string = offer.code
            toast("Code \(offer.code) copied — apply it in your cart")
        case .header:
            break
        }
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let urls: [URL] = indexPaths.compactMap { indexPath in
            switch dataSource.itemIdentifier(for: indexPath) {
            case .featured(let cafe), .nearby(let cafe): return cafe.imageURL
            case .dish(let dish): return dish.imageURL
            default: return nil
            }
        }
        ImagePipeline.shared.prefetch(urls, targetSize: CGSize(width: 320, height: 200))
    }
}

// MARK: - Model → card mapping

extension CafeCardModel {
    static func from(_ cafe: Cafe, offer: String? = nil) -> CafeCardModel {
        CafeCardModel(
            id: cafe.id,
            name: cafe.name,
            subtitle: cafe.cuisineText,
            imageURL: cafe.imageURL,
            rating: cafe.rating,
            deliveryMinutes: cafe.deliveryMinutes,
            distanceText: cafe.distanceKm.map { String(format: "%.1f km", $0) },
            isOpen: cafe.isOpenNow,
            offerText: offer ?? (cafe.deliveryFeePaise <= 1500 ? "Low delivery fee" : nil)
        )
    }
}

extension FoodItemCardModel {
    static func from(_ item: MenuItem, quantity: Int) -> FoodItemCardModel {
        FoodItemCardModel(
            id: item.id,
            name: item.name,
            description: item.description,
            priceText: Money.format(item.pricePaise),
            imageURL: item.imageURL,
            diet: DietIndicator.Diet(rawValue: item.diet.rawValue) ?? .veg,
            isBestseller: item.isBestseller,
            isAvailable: item.isAvailable,
            isCustomizable: item.isCustomizable,
            quantityInCart: quantity,
            caption: item.cafeName
        )
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Cells

final class HomeHeaderCell: UICollectionViewCell {
    static let reuseID = "HomeHeaderCell"
    var onLocationTap: (() -> Void)?
    var onSearchTap: (() -> Void)?

    private let etaLabel = UILabel(font: DK.Font.rounded(26, .heavy, style: .title1), color: DK.Color.textPrimary)
    private let greetingLabel = UILabel(font: DK.Font.callout, color: DK.Color.textSecondary)
    private let locationButton = UIButton(type: .system)
    private let searchButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        var locationConfig = UIButton.Configuration.plain()
        locationConfig.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        locationConfig.imagePlacement = .trailing
        locationConfig.imagePadding = 4
        locationConfig.contentInsets = .zero
        locationConfig.titleLineBreakMode = .byTruncatingTail
        locationButton.configuration = locationConfig
        locationButton.contentHorizontalAlignment = .leading
        locationButton.tintColor = DK.Color.textPrimary
        locationButton.accessibilityIdentifier = "homeLocation"
        locationButton.addAction(UIAction { [weak self] _ in self?.onLocationTap?() }, for: .touchUpInside)

        var searchConfig = UIButton.Configuration.filled()
        searchConfig.baseBackgroundColor = DK.Color.surface
        searchConfig.baseForegroundColor = DK.Color.textTertiary
        searchConfig.image = UIImage(systemName: "magnifyingglass")
        searchConfig.imagePadding = DK.Spacing.s
        searchConfig.title = "Search for “cold brew” or “croissant”"
        searchConfig.cornerStyle = .large
        searchConfig.contentInsets = .init(top: 14, leading: 14, bottom: 14, trailing: 14)
        searchConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = DK.Font.body
            return outgoing
        }
        searchButton.configuration = searchConfig
        searchButton.contentHorizontalAlignment = .leading
        searchButton.layer.borderColor = DK.Color.separator.cgColor
        searchButton.layer.borderWidth = 1
        searchButton.layer.cornerRadius = DK.Radius.m
        searchButton.accessibilityIdentifier = "homeSearch"
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearchTap?() }, for: .touchUpInside)

        let top = UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [greetingLabel, etaLabel, locationButton])
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.l, arrangedSubviews: [top, searchButton])
        contentView.addSubview(stack)
        stack.pinEdges(to: contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(greeting: String, locationTitle: String, locationSubtitle: String, etaMinutes: Int?) {
        greetingLabel.text = greeting
        etaLabel.text = etaMinutes.map { "Delivery in \($0) minutes ⚡" } ?? "QuickBite"
        var config = locationButton.configuration
        var title = AttributedString(locationTitle)
        title.font = DK.Font.bodyBold
        var subtitle = AttributedString(" · \(locationSubtitle)")
        subtitle.font = DK.Font.callout
        subtitle.foregroundColor = DK.Color.textSecondary
        config?.attributedTitle = title + subtitle
        locationButton.configuration = config
        locationButton.accessibilityLabel = "Delivering to \(locationTitle), \(locationSubtitle). Change location"
    }
}

final class OfferCell: UICollectionViewCell {
    static let reuseID = "OfferCell"
    private let gradient = CAGradientLayer()
    private let headline = UILabel(font: DK.Font.rounded(24, .heavy, style: .title1), color: .white, lines: 2)
    private let detail = UILabel(font: DK.Font.callout, color: UIColor.white.withAlphaComponent(0.9), lines: 2)
    private let code = PaddedLabel()

    private static let palettes: [(UInt32, UInt32)] = [(0xE2572B, 0xF29A3A), (0x5B3A29, 0x9C6B4E), (0x1E8E3E, 0x5FB878)]

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = DK.Radius.l
        contentView.layer.masksToBounds = true
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        contentView.layer.insertSublayer(gradient, at: 0)
        code.font = DK.Font.captionBold
        code.textColor = .white
        code.layer.borderColor = UIColor.white.cgColor
        code.layer.borderWidth = 1
        code.layer.cornerRadius = 6
        code.insets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        let icon = UIImageView(image: UIImage(systemName: "ticket.fill"))
        icon.tintColor = UIColor.white.withAlphaComponent(0.25)
        icon.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(icon)
        let codeRow = UIStackView(axis: .horizontal, arrangedSubviews: [code, UIView()])
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.xs, arrangedSubviews: [headline, detail, codeRow])
        stack.setCustomSpacing(DK.Spacing.s, after: detail)
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DK.Spacing.l),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DK.Spacing.xxxl),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            icon.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 10),
            icon.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 10),
            icon.widthAnchor.constraint(equalToConstant: 96),
            icon.heightAnchor.constraint(equalToConstant: 80),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Copies the coupon code"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = contentView.bounds
    }

    func configure(headline text: String, description: String, code codeText: String, index: Int) {
        headline.text = text
        detail.text = description
        code.text = "USE \(codeText)"
        let palette = Self.palettes[index % Self.palettes.count]
        gradient.colors = [DK.Color.hex(palette.0).cgColor, DK.Color.hex(palette.1).cgColor]
        accessibilityLabel = "\(text). \(description). Code \(codeText)"
    }
}

final class CategoryCell: UICollectionViewCell {
    static let reuseID = "CategoryCell"
    private let circle = UIView()
    private let icon = UIImageView()
    private let label = UILabel(font: DK.Font.caption, color: DK.Color.textPrimary, lines: 2)

    override init(frame: CGRect) {
        super.init(frame: frame)
        circle.backgroundColor = DK.Color.latte
        circle.layer.cornerRadius = 32
        circle.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = DK.Color.primary
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(icon)
        label.textAlignment = .center
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.s, alignment: .center, arrangedSubviews: [circle, label])
        contentView.addSubview(stack)
        stack.pinEdges(to: contentView)
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: 64),
            circle.heightAnchor.constraint(equalToConstant: 64),
            icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(name: String) {
        label.text = name
        icon.image = UIImage(systemName: Self.symbol(for: name))
        accessibilityLabel = name
        accessibilityIdentifier = "category_\(name)"
    }

    static func symbol(for category: String) -> String {
        let lower = category.lowercased()
        if lower.contains("coffee") { return "cup.and.saucer.fill" }
        if lower.contains("tea") { return "mug.fill" }
        if lower.contains("cold") || lower.contains("beverage") { return "takeoutbag.and.cup.and.straw.fill" }
        if lower.contains("dessert") { return "birthday.cake.fill" }
        if lower.contains("bakery") { return "basket.fill" }
        if lower.contains("pizza") || lower.contains("pasta") { return "fork.knife" }
        if lower.contains("burger") || lower.contains("sandwich") { return "takeoutbag.and.cup.and.straw" }
        if lower.contains("bowl") || lower.contains("salad") { return "leaf.fill" }
        if lower.contains("breakfast") { return "sun.horizon.fill" }
        return "fork.knife.circle.fill"
    }
}
