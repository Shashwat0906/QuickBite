import UIKit
import DesignKit
import NetworkKit

/// Cafe page: banner, info card, veg toggle, category jump menu and the menu.
final class CafeDetailViewController: UIViewController, UICollectionViewDelegate {
    private enum Item: Hashable {
        case info
        case dish(MenuItem)
    }

    private let viewModel: CafeDetailViewModel
    private weak var router: AppRouting?
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<String, Item>!
    private var cartObserver: NSObjectProtocol?
    private static let infoSection = "__info"

    init(viewModel: CafeDetailViewModel, router: AppRouting) {
        self.viewModel = viewModel
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let cartObserver { NotificationCenter.default.removeObserver(cartObserver) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DK.Color.background
        navigationItem.largeTitleDisplayMode = .never
        configureCollectionView()
        configureDataSource()
        viewModel.onStateChange = { [weak self] state in self?.render(state) }
        cartObserver = NotificationCenter.default.addObserver(forName: .cartDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshVisibleQuantities() }
        }
        render(.loading)
        viewModel.load()
    }

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.backgroundColor = DK.Color.background
        config.showsSeparators = false
        config.headerMode = .supplementary
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
            section.contentInsets = .init(top: 0, leading: DK.Spacing.page, bottom: DK.Spacing.l, trailing: DK.Spacing.page)
            if self?.dataSource?.snapshot().sectionIdentifiers[safe: index] == Self.infoSection {
                section.boundarySupplementaryItems = []
                section.contentInsets.leading = 0
                section.contentInsets.trailing = 0
            }
            return section
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = DK.Color.background
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "cafeMenu"
        collectionView.register(FoodItemCell.self, forCellWithReuseIdentifier: FoodItemCell.reuseID)
        collectionView.register(CafeInfoCell.self, forCellWithReuseIdentifier: CafeInfoCell.reuseID)
        collectionView.register(MenuSectionHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: MenuSectionHeader.reuseID)
        view.addSubview(collectionView)
        collectionView.pinEdges(to: view)

        let menuButton = UIBarButtonItem(image: UIImage(systemName: "list.bullet"), menu: nil)
        menuButton.accessibilityLabel = "Jump to menu section"
        navigationItem.rightBarButtonItem = menuButton
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<String, Item>(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            guard let self else { return nil }
            switch item {
            case .info:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CafeInfoCell.reuseID, for: indexPath) as! CafeInfoCell
                if let cafe = self.viewModel.cafe {
                    cell.configure(cafe: cafe, vegOnly: self.viewModel.vegOnly)
                    cell.onVegToggle = { [weak self] isOn in self?.setVegOnly(isOn) }
                    cell.onReviews = { [weak self] in self?.router?.showCafeReviews(cafe: cafe) }
                }
                return cell
            case .dish(let dish):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FoodItemCell.reuseID, for: indexPath) as! FoodItemCell
                cell.configure(FoodItemCardModel.from(dish, quantity: self.viewModel.quantity(of: dish)).withoutCafeCaption)
                cell.onQuantityChange = { [weak self, weak cell] value in
                    guard let self else { return }
                    self.handleQuantity(value, for: dish, cell: cell)
                }
                return cell
            }
        }
        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MenuSectionHeader.reuseID, for: indexPath) as! MenuSectionHeader
            let name = self?.dataSource.snapshot().sectionIdentifiers[safe: indexPath.section] ?? ""
            let count = self?.dataSource.snapshot().numberOfItems(inSection: name) ?? 0
            header.configure(title: name == Self.infoSection ? "" : name, count: count)
            return header
        }
    }

    private func render(_ state: CafeDetailViewModel.State) {
        switch state {
        case .loading:
            installOverlay(SkeletonListView(rows: 6))
        case .failed(let error):
            installOverlay(makeStateView(for: error) { [weak self] in self?.viewModel.load() })
        case .loaded(let cafe, _):
            installOverlay(nil)
            title = cafe.name
            applySnapshot()
            updateJumpMenu()
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<String, Item>()
        snapshot.appendSections([Self.infoSection])
        snapshot.appendItems([.info], toSection: Self.infoSection)
        for section in viewModel.visibleSections {
            snapshot.appendSections([section.name])
            snapshot.appendItems(section.items.map(Item.dish), toSection: section.name)
        }
        snapshot.reconfigureItems([.info])
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func updateJumpMenu() {
        let actions = viewModel.visibleSections.enumerated().map { offset, section in
            UIAction(title: "\(section.name) (\(section.items.count))") { [weak self] _ in
                self?.collectionView.scrollToItem(at: IndexPath(item: 0, section: offset + 1), at: .top, animated: true)
            }
        }
        navigationItem.rightBarButtonItem?.menu = UIMenu(title: "Menu", children: actions)
    }

    private func setVegOnly(_ isOn: Bool) {
        viewModel.vegOnly = isOn
        Haptics.selection()
        applySnapshot()
        updateJumpMenu()
    }

    private func refreshVisibleQuantities() {
        var snapshot = dataSource.snapshot()
        let dishes = snapshot.itemIdentifiers.filter { if case .dish = $0 { return true } else { return false } }
        snapshot.reconfigureItems(dishes)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: Cart interactions

    private func handleQuantity(_ value: Int, for dish: MenuItem, cell: FoodItemCell?) {
        switch viewModel.setQuantity(value, for: dish) {
        case .added:
            break
        case .needsCustomization(let item):
            refreshVisibleQuantities() // reset the stepper back to ADD until the sheet confirms
            presentCustomization(for: item)
        case .conflict(let current, let retry):
            refreshVisibleQuantities()
            confirm(title: "Replace cart items?", message: "Your cart has items from \(current). Start a new cart with \(viewModel.cafe?.name ?? "this cafe")?", confirmTitle: "Replace") {
                retry()
                if dish.isCustomizable { self.presentCustomization(for: dish, replacing: true) }
            }
        case .unavailable:
            refreshVisibleQuantities()
            toast("\(dish.name) is unavailable right now", style: .error)
        }
    }

    private func presentCustomization(for item: MenuItem, replacing: Bool = false) {
        guard let cafe = viewModel.cafe else { return }
        let sheet = ItemCustomizationViewController(viewModel: ItemCustomizationViewModel(item: item))
        sheet.onConfirm = { [weak self] optionIds, quantity in
            guard let self else { return }
            do {
                try self.viewModel.addConfigured(item, from: cafe, optionIds: optionIds, quantity: quantity, replacingOtherCafe: replacing)
                Haptics.success()
            } catch CartError.differentCafe(let current) {
                self.confirm(title: "Replace cart items?", message: "Your cart has items from \(current).", confirmTitle: "Replace") {
                    try? self.viewModel.addConfigured(item, from: cafe, optionIds: optionIds, quantity: quantity, replacingOtherCafe: true)
                }
            } catch {
                self.toast("You've reached the maximum quantity", style: .error)
            }
        }
        let nav = UINavigationController(rootViewController: sheet)
        if let presentation = nav.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard case .dish(let dish) = dataSource.itemIdentifier(for: indexPath), dish.isAvailable else { return }
        presentCustomization(for: dish)
    }
}

private extension FoodItemCardModel {
    /// Inside a cafe page we don't repeat the cafe name under each dish.
    var withoutCafeCaption: FoodItemCardModel {
        var copy = self
        copy.caption = nil
        return copy
    }
}

/// Banner + cafe facts + veg toggle at the top of the menu.
final class CafeInfoCell: UICollectionViewCell {
    static let reuseID = "CafeInfoCell"
    var onVegToggle: ((Bool) -> Void)?
    var onReviews: (() -> Void)?

    private let banner = RemoteImageView()
    private let nameLabel = UILabel(font: DK.Font.title, lines: 2)
    private let cuisineLabel = UILabel(font: DK.Font.callout, color: DK.Color.textSecondary)
    private let addressLabel = UILabel(font: DK.Font.caption, color: DK.Color.textTertiary, lines: 2)
    private let rating = RatingBadge()
    private let ratingCount = UIButton(type: .system)
    private let statsLabel = UILabel(font: DK.Font.bodyBold, lines: 0)
    private let statusLabel = PaddedLabel()
    private let vegSwitch = UISwitch()

    override init(frame: CGRect) {
        super.init(frame: frame)
        banner.layer.cornerRadius = 0
        statusLabel.font = DK.Font.captionBold
        statusLabel.layer.cornerRadius = 6
        statusLabel.layer.masksToBounds = true
        ratingCount.titleLabel?.font = DK.Font.caption
        ratingCount.addAction(UIAction { [weak self] _ in self?.onReviews?() }, for: .touchUpInside)
        vegSwitch.onTintColor = DK.Color.veg
        vegSwitch.accessibilityIdentifier = "vegOnlySwitch"
        vegSwitch.addAction(UIAction { [weak self] _ in self?.onVegToggle?(self?.vegSwitch.isOn ?? false) }, for: .valueChanged)

        let ratingRow = UIStackView(axis: .horizontal, spacing: DK.Spacing.s, alignment: .center, arrangedSubviews: [rating, ratingCount, UIView(), statusLabel])
        let vegLabel = UILabel(font: DK.Font.bodyBold, text: "Veg only")
        let vegIcon = DietIndicator(.veg)
        let vegRow = UIStackView(axis: .horizontal, spacing: DK.Spacing.s, alignment: .center, arrangedSubviews: [vegIcon, vegLabel, UIView(), vegSwitch])
        let divider = UIView()
        divider.backgroundColor = DK.Color.separator
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let card = UIStackView(axis: .vertical, spacing: DK.Spacing.s, arrangedSubviews: [nameLabel, cuisineLabel, addressLabel, ratingRow, statsLabel, divider, vegRow])
        card.setCustomSpacing(DK.Spacing.m, after: addressLabel)
        card.setCustomSpacing(DK.Spacing.m, after: statsLabel)
        let cardView = CardView(content: card)

        contentView.addSubview(banner)
        contentView.addSubview(cardView)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: contentView.topAnchor),
            banner.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            banner.heightAnchor.constraint(equalToConstant: 190),
            cardView.topAnchor.constraint(equalTo: banner.bottomAnchor, constant: -36),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DK.Spacing.page),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DK.Spacing.page),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -DK.Spacing.s),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(cafe: Cafe, vegOnly: Bool) {
        banner.setImage(url: cafe.bannerURL)
        nameLabel.text = cafe.name
        nameLabel.accessibilityTraits = .header
        cuisineLabel.text = cafe.cuisineText
        addressLabel.text = cafe.addressLine
        rating.set(rating: cafe.rating)
        ratingCount.setTitle("\(cafe.ratingCount) ratings ›", for: .normal)
        var stats: [String] = []
        if let minutes = cafe.deliveryMinutes { stats.append("⚡ \(minutes) min") }
        if let km = cafe.distanceKm { stats.append(String(format: "%.1f km", km)) }
        stats.append(cafe.deliveryFeePaise == 0 ? "Free delivery" : "\(Money.format(cafe.deliveryFeePaise)) delivery")
        statsLabel.text = stats.joined(separator: "  ·  ")
        statusLabel.text = cafe.isOpenNow ? "Open now" : "Closed · opens \(cafe.opensAt)"
        statusLabel.textColor = cafe.isOpenNow ? DK.Color.success : DK.Color.error
        statusLabel.backgroundColor = (cafe.isOpenNow ? DK.Color.success : DK.Color.error).withAlphaComponent(0.12)
        vegSwitch.isOn = vegOnly
    }
}

final class MenuSectionHeader: UICollectionReusableView {
    static let reuseID = "MenuSectionHeader"
    private let label = UILabel(font: DK.Font.title2)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DK.Color.background
        addSubview(label)
        label.pinEdges(to: self, insets: UIEdgeInsets(top: DK.Spacing.l, left: 0, bottom: DK.Spacing.xs, right: 0))
        label.accessibilityTraits = .header
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(title: String, count: Int) {
        label.text = title.isEmpty ? nil : "\(title) (\(count))"
        isHidden = title.isEmpty
    }
}

/// Bottom sheet: pick size / milk / extras and quantity, see the price update live.
final class ItemCustomizationViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onConfirm: (([String], Int) -> Void)?
    private let viewModel: ItemCustomizationViewModel
    private let confirmTitle: String
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let addButton = QBButton(title: "")
    private let stepper = UIStepper()
    private let quantityLabel = UILabel(font: DK.Font.headline)

    init(viewModel: ItemCustomizationViewModel, confirmTitle: String = "Add to cart") {
        self.viewModel = viewModel
        self.confirmTitle = confirmTitle
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DK.Color.background
        title = viewModel.item.name
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = DK.Color.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "option")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.accessibilityIdentifier = "customizationTable"

        stepper.minimumValue = 1
        stepper.maximumValue = Double(CartStore.maxQuantityPerLine)
        stepper.value = Double(viewModel.quantity)
        stepper.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.viewModel.setQuantity(Int(self.stepper.value))
            self.updateFooter()
        }, for: .valueChanged)
        addButton.accessibilityIdentifier = "confirmCustomization"
        addButton.addAction(UIAction { [weak self] _ in self?.confirmTapped() }, for: .touchUpInside)

        let qtyRow = UIStackView(axis: .horizontal, spacing: DK.Spacing.m, alignment: .center, arrangedSubviews: [quantityLabel, stepper])
        let footer = UIStackView(axis: .horizontal, spacing: DK.Spacing.l, alignment: .center, arrangedSubviews: [qtyRow, addButton])
        footer.isLayoutMarginsRelativeArrangement = true
        footer.directionalLayoutMargins = .init(top: DK.Spacing.m, leading: DK.Spacing.page, bottom: DK.Spacing.m, trailing: DK.Spacing.page)
        footer.backgroundColor = DK.Color.surface
        view.addSubview(tableView)
        view.addSubview(footer)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        updateFooter()
    }

    private func updateFooter() {
        quantityLabel.text = "\(viewModel.quantity)"
        addButton.setTitle("\(confirmTitle) · \(Money.format(viewModel.totalPrice))")
        addButton.accessibilityLabel = "\(confirmTitle), \(Money.spoken(viewModel.totalPrice))"
    }

    private func confirmTapped() {
        if let message = viewModel.validationMessage {
            toast(message, style: .error)
            Haptics.error()
            return
        }
        onConfirm?(viewModel.selectedIds, viewModel.quantity)
        dismiss(animated: true)
    }

    func numberOfSections(in tableView: UITableView) -> Int { viewModel.item.customizations.count + 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 0 : viewModel.item.customizations[section - 1].options.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section > 0 else { return nil }
        let group = viewModel.item.customizations[section - 1]
        let rule = group.isRequired ? "Required · choose \(group.minSelect)" : "Optional · up to \(group.maxSelect)"
        return "\(group.name) — \(rule)"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "\(viewModel.item.description)\nBase price \(Money.format(viewModel.item.pricePaise))" : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "option", for: indexPath)
        let group = viewModel.item.customizations[indexPath.section - 1]
        let option = group.options[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = option.name
        content.secondaryText = option.extraPricePaise > 0 ? "+ \(Money.format(option.extraPricePaise))" : nil
        content.textProperties.color = option.isAvailable ? DK.Color.textPrimary : DK.Color.textTertiary
        cell.contentConfiguration = content
        let selected = viewModel.isSelected(option)
        let symbol = group.isSingleChoice ? (selected ? "largecircle.fill.circle" : "circle") : (selected ? "checkmark.square.fill" : "square")
        let check = UIImageView(image: UIImage(systemName: symbol))
        check.tintColor = DK.Color.primary
        cell.accessoryView = check
        cell.accessibilityTraits = selected ? [.button, .selected] : .button
        cell.accessibilityIdentifier = "option_\(option.name)"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let group = viewModel.item.customizations[indexPath.section - 1]
        if let message = viewModel.toggle(group.options[indexPath.row], in: group) {
            toast(message, style: .error)
        } else {
            Haptics.selection()
        }
        tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        updateFooter()
    }
}

/// "See all" / category list of cafes with sort + filters and infinite scroll.
final class CafeListViewController: UIViewController, UICollectionViewDelegate {
    private let viewModel: CafeListViewModel
    private weak var router: AppRouting?
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Cafe>!

    init(viewModel: CafeListViewModel, router: AppRouting) {
        self.viewModel = viewModel
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.title
        view.backgroundColor = DK.Color.background
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(260)))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(260)), subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = DK.Spacing.l
            section.contentInsets = .init(top: DK.Spacing.l, leading: DK.Spacing.page, bottom: DK.Spacing.l, trailing: DK.Spacing.page)
            return section
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = DK.Color.background
        collectionView.delegate = self
        collectionView.register(CafeCardCell.self, forCellWithReuseIdentifier: CafeCardCell.reuseID)
        view.addSubview(collectionView)
        collectionView.pinEdges(to: view)
        dataSource = UICollectionViewDiffableDataSource<Int, Cafe>(collectionView: collectionView) { collectionView, indexPath, cafe in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CafeCardCell.reuseID, for: indexPath) as! CafeCardCell
            cell.configure(CafeCardModel.from(cafe))
            return cell
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease.circle"), menu: makeFilterMenu())
        viewModel.onChange = { [weak self] result in self?.render(result) }
        installOverlay(SkeletonListView(rows: 4))
        viewModel.reload()
    }

    private func makeFilterMenu() -> UIMenu {
        let sorts = [("distance", "Nearest"), ("rating", "Top rated"), ("deliveryTime", "Fastest delivery")].map { key, title in
            UIAction(title: title, state: viewModel.sort == key ? .on : .off) { [weak self] _ in
                self?.viewModel.sort = key
                self?.refreshFilters()
            }
        }
        let open = UIAction(title: "Open now", image: UIImage(systemName: "clock"), state: viewModel.openNow ? .on : .off) { [weak self] _ in
            guard let self else { return }
            self.viewModel.openNow.toggle()
            self.refreshFilters()
        }
        let rated = UIAction(title: "Rating 4.5+", image: UIImage(systemName: "star"), state: viewModel.minRating != nil ? .on : .off) { [weak self] _ in
            guard let self else { return }
            self.viewModel.minRating = self.viewModel.minRating == nil ? 4.5 : nil
            self.refreshFilters()
        }
        return UIMenu(children: [UIMenu(title: "Sort by", options: .displayInline, children: sorts), UIMenu(title: "Filter", options: .displayInline, children: [open, rated])])
    }

    private func refreshFilters() {
        navigationItem.rightBarButtonItem?.menu = makeFilterMenu()
        installOverlay(SkeletonListView(rows: 4))
        viewModel.reload()
    }

    private func render(_ result: Result<[Cafe], APIError>) {
        switch result {
        case .success(let cafes):
            if cafes.isEmpty {
                installOverlay(StateView(.empty(symbol: "cup.and.saucer", title: "No cafés found", message: "Try removing a filter.")))
            } else {
                installOverlay(nil)
            }
            var snapshot = NSDiffableDataSourceSnapshot<Int, Cafe>()
            snapshot.appendSections([0])
            snapshot.appendItems(cafes.uniqued())
            dataSource.apply(snapshot, animatingDifferences: true)
        case .failure(let error):
            installOverlay(makeStateView(for: error) { [weak self] in self?.viewModel.reload() })
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cafe = dataSource.itemIdentifier(for: indexPath) else { return }
        router?.showCafe(id: cafe.id)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.item >= dataSource.snapshot().numberOfItems - 2 { viewModel.loadNextPage() }
    }
}

extension Array where Element: Hashable {
    /// Removes duplicates keeping the first occurrence (diffable data sources require unique items).
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
