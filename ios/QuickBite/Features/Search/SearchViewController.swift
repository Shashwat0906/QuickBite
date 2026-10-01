import UIKit
import DesignKit

/// Search tab: search field, filter chips, sort menu, recent/suggested
/// searches when idle, and results with the matched text highlighted.
final class SearchViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private let viewModel: SearchViewModel
    private weak var router: AppRouting?
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let chipsScroll = UIScrollView()
    private let vegChip = ChipButton(title: "Veg only", symbol: "leaf.fill")
    private let ratingChip = ChipButton(title: "Rating 4.5+", symbol: "star.fill")
    private let priceChip = ChipButton(title: "Under ₹250", symbol: "indianrupeesign")
    private let availableChip = ChipButton(title: "Available now", symbol: "checkmark.circle")
    private let sortChip = ChipButton(title: "Sort", symbol: "arrow.up.arrow.down")
    private var state: SearchViewModel.State = .loading

    init(viewModel: SearchViewModel, router: AppRouting) {
        self.viewModel = viewModel
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Search"
        view.backgroundColor = DK.Color.background
        searchBar.placeholder = "Search cafés, coffee, desserts…"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.returnKeyType = .search
        searchBar.searchTextField.accessibilityIdentifier = "searchField"
        searchBar.translatesAutoresizingMaskIntoConstraints = false

        configureChips()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = DK.Color.background
        tableView.keyboardDismissMode = .onDrag
        tableView.separatorStyle = .none
        tableView.accessibilityIdentifier = "searchResults"
        tableView.register(SearchResultCell.self, forCellReuseIdentifier: SearchResultCell.reuseID)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "plain")
        tableView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchBar)
        view.addSubview(chipsScroll)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DK.Spacing.s),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DK.Spacing.s),
            chipsScroll.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            chipsScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chipsScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chipsScroll.heightAnchor.constraint(equalToConstant: 48),
            tableView.topAnchor.constraint(equalTo: chipsScroll.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        viewModel.onStateChange = { [weak self] state in self?.render(state) }
        render(viewModel.state)
        viewModel.loadSuggestions()
    }

    /// Entry point from Home's search bar / category taps.
    func startSearch(query: String?) {
        loadViewIfNeeded()
        if let query, !query.isEmpty {
            searchBar.text = query
            viewModel.submit(query)
        } else {
            DispatchQueue.main.async { self.searchBar.becomeFirstResponder() }
        }
    }

    private func configureChips() {
        chipsScroll.showsHorizontalScrollIndicator = false
        chipsScroll.translatesAutoresizingMaskIntoConstraints = false
        let row = UIStackView(axis: .horizontal, spacing: DK.Spacing.s, alignment: .center, arrangedSubviews: [sortChip, vegChip, ratingChip, priceChip, availableChip])
        chipsScroll.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.leadingAnchor, constant: DK.Spacing.page),
            row.trailingAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.trailingAnchor, constant: -DK.Spacing.page),
            row.centerYAnchor.constraint(equalTo: chipsScroll.frameLayoutGuide.centerYAnchor),
            row.topAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.bottomAnchor),
        ])
        vegChip.accessibilityIdentifier = "filterVeg"
        vegChip.addAction(UIAction { [weak self] _ in self?.toggle(\.vegOnly) }, for: .touchUpInside)
        availableChip.addAction(UIAction { [weak self] _ in self?.toggle(\.availableOnly) }, for: .touchUpInside)
        ratingChip.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.viewModel.filters.minRating = self.viewModel.filters.minRating == nil ? 4.5 : nil
            self.syncChips()
        }, for: .touchUpInside)
        priceChip.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.viewModel.filters.maxPricePaise = self.viewModel.filters.maxPricePaise == nil ? 25_000 : nil
            self.syncChips()
        }, for: .touchUpInside)
        sortChip.showsMenuAsPrimaryAction = true
        sortChip.menu = makeSortMenu()
    }

    private func makeSortMenu() -> UIMenu {
        UIMenu(title: "Sort by", children: SearchFilters.Sort.allCases.map { sort in
            UIAction(title: sort.title, state: viewModel.filters.sort == sort ? .on : .off) { [weak self] _ in
                self?.viewModel.filters.sort = sort
                self?.syncChips()
            }
        })
    }

    private func toggle(_ keyPath: WritableKeyPath<SearchFilters, Bool>) {
        viewModel.filters[keyPath: keyPath].toggle()
        Haptics.selection()
        syncChips()
    }

    private func syncChips() {
        let filters = viewModel.filters
        vegChip.isOn = filters.vegOnly
        availableChip.isOn = filters.availableOnly
        ratingChip.isOn = filters.minRating != nil
        priceChip.isOn = filters.maxPricePaise != nil
        sortChip.isOn = filters.sort != .relevance
        sortChip.configuration?.title = filters.sort == .relevance ? "Sort" : filters.sort.title
        sortChip.menu = makeSortMenu()
    }

    private func render(_ state: SearchViewModel.State) {
        self.state = state
        switch state {
        case .loading:
            installOverlay(SkeletonListView(rows: 5), in: view, tag: 9_100, below: chipsScroll.bottomAnchor)
            tableView.reloadData()
            return
        case .empty(let query):
            installOverlay(StateView(.empty(symbol: "magnifyingglass", title: "No results for “\(query)”", message: "Check the spelling or try something broader, like “coffee”.")), in: view, tag: 9_100, below: chipsScroll.bottomAnchor)
        case .failed(let message):
            installOverlay(StateView(.error(title: "Search failed", message: message), actionTitle: "Try again") { [weak self] in
                self?.viewModel.submit(self?.viewModel.query ?? "")
            }, in: view, tag: 9_100, below: chipsScroll.bottomAnchor)
        default:
            installOverlay(nil, in: view, tag: 9_100)
        }
        tableView.reloadData()
    }

    // MARK: Table

    private enum Row {
        case term(String, isRecent: Bool)
        case category(String)
        case cafe(Cafe)
        case item(MenuItem)
        case clearRecent
    }

    private var sections: [(title: String?, rows: [Row])] {
        switch state {
        case let .idle(recent, suggestions, categories):
            var result: [(title: String?, rows: [Row])] = []
            if !recent.isEmpty { result.append(("Recent searches", recent.map { .term($0, isRecent: true) } + [.clearRecent])) }
            if !suggestions.isEmpty { result.append(("Trending", suggestions.map { .term($0, isRecent: false) })) }
            if !categories.isEmpty { result.append(("Browse categories", categories.map(Row.category))) }
            return result
        case let .results(cafes, items, _):
            var result: [(title: String?, rows: [Row])] = []
            if !cafes.isEmpty { result.append(("Cafés", cafes.map(Row.cafe))) }
            if !items.isEmpty { result.append(("Dishes", items.map(Row.item))) }
            return result
        default:
            return []
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section].rows[indexPath.row] {
        case let .term(text, isRecent):
            let cell = tableView.dequeueReusableCell(withIdentifier: "plain", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = text
            content.image = UIImage(systemName: isRecent ? "clock.arrow.circlepath" : "arrow.up.right")
            content.imageProperties.tintColor = DK.Color.textTertiary
            cell.contentConfiguration = content
            cell.backgroundColor = .clear
            return cell
        case .category(let name):
            let cell = tableView.dequeueReusableCell(withIdentifier: "plain", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = name
            content.image = UIImage(systemName: CategoryCell.symbol(for: name))
            content.imageProperties.tintColor = DK.Color.primary
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            cell.backgroundColor = .clear
            return cell
        case .clearRecent:
            let cell = tableView.dequeueReusableCell(withIdentifier: "plain", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Clear recent searches"
            content.textProperties.color = DK.Color.primary
            cell.contentConfiguration = content
            cell.backgroundColor = .clear
            return cell
        case .cafe(let cafe):
            let cell = tableView.dequeueReusableCell(withIdentifier: SearchResultCell.reuseID, for: indexPath) as! SearchResultCell
            let meta = [cafe.deliveryMinutes.map { "⚡ \($0) min" }, String(format: "★ %.1f", cafe.rating), cafe.isOpenNow ? nil : "Closed"].compactMap { $0 }.joined(separator: "  ·  ")
            cell.configure(title: cafe.name, subtitle: cafe.cuisineText, meta: meta, imageURL: cafe.imageURL, highlight: viewModel.query, diet: nil)
            return cell
        case .item(let item):
            let cell = tableView.dequeueReusableCell(withIdentifier: SearchResultCell.reuseID, for: indexPath) as! SearchResultCell
            let meta = "\(Money.format(item.pricePaise))\(item.isAvailable ? "" : "  ·  Unavailable")"
            cell.configure(title: item.name, subtitle: item.cafeName ?? "", meta: meta, imageURL: item.imageURL, highlight: viewModel.query, diet: item.diet)
            cell.accessibilityIdentifier = "searchItem_\(item.name)"
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case .term(let text, _):
            searchBar.text = text
            searchBar.resignFirstResponder()
            viewModel.submit(text)
        case .category(let name):
            viewModel.filters.category = name
            searchBar.text = ""
            viewModel.submit("")
            toast("Showing \(name)", style: .info)
        case .clearRecent:
            viewModel.clearRecent()
        case .cafe(let cafe):
            router?.showCafe(id: cafe.id)
        case .item(let item):
            router?.showCafe(id: item.cafeId)
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.section == sections.count - 1, indexPath.row >= sections[indexPath.section].rows.count - 3 {
            viewModel.loadMore()
        }
    }

    // MARK: UISearchBarDelegate

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty { viewModel.filters.category = nil }
        viewModel.updateQuery(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        viewModel.submit(searchBar.text ?? "")
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) { searchBar.setShowsCancelButton(true, animated: true) }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.setShowsCancelButton(false, animated: true)
        searchBar.resignFirstResponder()
        viewModel.filters = SearchFilters()
        syncChips()
        viewModel.updateQuery("")
    }
}

/// Result row with the search term highlighted in bold accent colour.
final class SearchResultCell: UITableViewCell {
    static let reuseID = "SearchResultCell"
    private let thumb = RemoteImageView()
    private let titleLabel = UILabel(font: DK.Font.headline)
    private let subtitleLabel = UILabel(font: DK.Font.caption, color: DK.Color.textSecondary)
    private let metaLabel = UILabel(font: DK.Font.captionBold, color: DK.Color.textPrimary)
    private let diet = DietIndicator()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .default
        thumb.layer.cornerRadius = DK.Radius.m
        let titleRow = UIStackView(axis: .horizontal, spacing: DK.Spacing.xs, alignment: .center, arrangedSubviews: [diet, titleLabel])
        let text = UIStackView(axis: .vertical, spacing: 3, arrangedSubviews: [titleRow, subtitleLabel, metaLabel])
        let row = UIStackView(axis: .horizontal, spacing: DK.Spacing.m, alignment: .center, arrangedSubviews: [thumb, text])
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: UIEdgeInsets(top: DK.Spacing.s, left: DK.Spacing.page, bottom: DK.Spacing.s, right: DK.Spacing.page))
        NSLayoutConstraint.activate([thumb.widthAnchor.constraint(equalToConstant: 64), thumb.heightAnchor.constraint(equalToConstant: 64)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(title: String, subtitle: String, meta: String, imageURL: URL?, highlight: String, diet dietValue: Diet?) {
        titleLabel.attributedText = Self.highlighted(title, term: highlight)
        subtitleLabel.text = subtitle
        metaLabel.text = meta
        thumb.setImage(url: imageURL)
        diet.isHidden = dietValue == nil
        if let dietValue { diet.set(DietIndicator.Diet(rawValue: dietValue.rawValue) ?? .veg) }
        accessibilityLabel = [title, subtitle, meta].joined(separator: ", ")
    }

    static func highlighted(_ text: String, term: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: DK.Font.headline, .foregroundColor: DK.Color.textPrimary])
        guard !term.isEmpty else { return result }
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            result.addAttributes([.foregroundColor: DK.Color.primary, .underlineStyle: NSUnderlineStyle.single.rawValue], range: NSRange(range, in: text))
            searchRange = range.upperBound..<text.endIndex
        }
        return result
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumb.cancel()
    }
}
