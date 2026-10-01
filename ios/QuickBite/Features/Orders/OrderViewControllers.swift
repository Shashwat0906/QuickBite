import UIKit
import MapKit
import DesignKit

/// Orders tab: Active / Past segments, pull to refresh, reorder and rate.
final class OrdersViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let viewModel: OrdersViewModel
    private weak var router: AppRouting?
    private let segmented = UISegmentedControl(items: ["Active", "Past orders"])
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var observer: NSObjectProtocol?

    init(viewModel: OrdersViewModel, router: AppRouting) {
        self.viewModel = viewModel
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Orders"
        view.backgroundColor = DK.Color.background
        segmented.selectedSegmentIndex = 0
        segmented.accessibilityIdentifier = "ordersSegment"
        segmented.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.viewModel.filter = OrdersViewModel.Filter(rawValue: self.segmented.selectedSegmentIndex) ?? .active
            self.viewModel.load()
        }, for: .valueChanged)
        segmented.translatesAutoresizingMaskIntoConstraints = false

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = DK.Color.background
        tableView.register(OrderCell.self, forCellReuseIdentifier: OrderCell.reuseID)
        tableView.accessibilityIdentifier = "ordersTable"
        tableView.translatesAutoresizingMaskIntoConstraints = false
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self] _ in self?.viewModel.load() }, for: .valueChanged)
        tableView.refreshControl = refresh

        view.addSubview(segmented)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            segmented.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DK.Spacing.s),
            segmented.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DK.Spacing.page),
            segmented.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DK.Spacing.page),
            tableView.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: DK.Spacing.s),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        viewModel.onChange = { [weak self] in self?.render() }
        observer = NotificationCenter.default.addObserver(forName: .sessionDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.viewModel.load() }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.load()
    }

    private func render() {
        if !viewModel.isLoading { tableView.refreshControl?.endRefreshing() }
        tableView.reloadData()
        let overlay: UIView?
        if !viewModel.session.isSignedIn {
            overlay = StateView(.empty(symbol: "bag", title: "Sign in to see your orders", message: "Your current and past orders will show up here."), actionTitle: "Sign in") { [weak self] in
                self?.router?.requireSignIn(reason: "Sign in to see your orders") { self?.viewModel.load() }
            }
        } else if let error = viewModel.error, viewModel.items.isEmpty {
            overlay = makeStateView(for: error) { [weak self] in self?.viewModel.load() }
        } else if viewModel.items.isEmpty && !viewModel.isLoading {
            overlay = viewModel.filter == .active
                ? StateView(.empty(symbol: "takeoutbag.and.cup.and.straw", title: "No active orders", message: "Hungry? Your next favourite is minutes away."))
                : StateView(.empty(symbol: "clock.arrow.circlepath", title: "No past orders yet", message: "Orders you've received will appear here."))
        } else {
            overlay = nil
        }
        installOverlay(overlay, in: view, below: segmented.bottomAnchor)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { viewModel.items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let order = viewModel.items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: OrderCell.reuseID, for: indexPath) as! OrderCell
        cell.configure(order)
        cell.onReorder = { [weak self] in self?.reorder(order) }
        cell.onRate = { [weak self] in
            self?.router?.showWriteReview(orderId: order.id, cafeName: order.cafe?.name ?? "the café") { self?.viewModel.load() }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        router?.showOrder(id: viewModel.items[indexPath.row].id)
    }

    private func reorder(_ order: OrderSummary) {
        Task {
            do {
                let skipped = try await viewModel.reorder(order)
                if !skipped.isEmpty { toast("Unavailable now: \(skipped.joined(separator: ", "))", style: .info) }
                router?.showCart()
            } catch {
                showError(error, title: "Couldn't reorder")
            }
        }
    }
}

final class OrderCell: UITableViewCell {
    static let reuseID = "OrderCell"
    var onReorder: (() -> Void)?
    var onRate: (() -> Void)?

    private let thumb = RemoteImageView()
    private let cafeLabel = UILabel(font: DK.Font.headline)
    private let itemsLabel = UILabel(font: DK.Font.caption, color: DK.Color.textSecondary, lines: 2)
    private let metaLabel = UILabel(font: DK.Font.caption, color: DK.Color.textTertiary)
    private let statusLabel = PaddedLabel()
    private let reorderButton = QBButton(title: "Reorder", style: .outline)
    private let rateButton = QBButton(title: "Rate", style: .text, image: UIImage(systemName: "star"))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        thumb.layer.cornerRadius = DK.Radius.m
        statusLabel.font = DK.Font.captionBold
        statusLabel.layer.cornerRadius = 6
        statusLabel.layer.masksToBounds = true
        reorderButton.addAction(UIAction { [weak self] _ in self?.onReorder?() }, for: .touchUpInside)
        rateButton.addAction(UIAction { [weak self] _ in self?.onRate?() }, for: .touchUpInside)
        for button in [reorderButton, rateButton] {
            button.configuration?.buttonSize = .small
            button.constraints.filter { $0.firstAttribute == .height }.forEach { $0.constant = 36 }
        }
        let header = UIStackView(axis: .horizontal, spacing: DK.Spacing.s, alignment: .center, arrangedSubviews: [cafeLabel, UIView(), statusLabel])
        let text = UIStackView(axis: .vertical, spacing: 3, arrangedSubviews: [header, itemsLabel, metaLabel])
        let top = UIStackView(axis: .horizontal, spacing: DK.Spacing.m, alignment: .top, arrangedSubviews: [thumb, text])
        let actions = UIStackView(axis: .horizontal, spacing: DK.Spacing.s, arrangedSubviews: [rateButton, UIView(), reorderButton])
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.m, arrangedSubviews: [top, actions])
        contentView.addSubview(stack)
        stack.pinEdges(to: contentView, insets: UIEdgeInsets(top: DK.Spacing.m, left: DK.Spacing.l, bottom: DK.Spacing.m, right: DK.Spacing.l))
        NSLayoutConstraint.activate([thumb.widthAnchor.constraint(equalToConstant: 56), thumb.heightAnchor.constraint(equalToConstant: 56)])
        accessoryType = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ order: OrderSummary) {
        thumb.setImage(url: order.cafe.flatMap { URL(string: $0.imageUrl) })
        cafeLabel.text = order.cafe?.name ?? "Order"
        itemsLabel.text = order.itemsPreview
        metaLabel.text = "\(order.orderNumber) · \(order.createdAt.orderDateText) · \(Money.format(order.totalPaise))"
        statusLabel.text = order.status.title
        let color: UIColor = order.status == .delivered ? DK.Color.success : order.status == .cancelled ? DK.Color.error : DK.Color.primary
        statusLabel.textColor = color
        statusLabel.backgroundColor = color.withAlphaComponent(0.12)
        let isPast = order.status.isFinal
        reorderButton.isHidden = !isPast
        rateButton.isHidden = !(order.status == .delivered && !order.isReviewed)
        accessibilityIdentifier = "order_\(order.orderNumber)"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumb.cancel()
    }
}

/// Live tracking: progress steps, ETA, map (demo rider clearly labelled),
/// order details, bill, support, cancel / rate / reorder.
final class OrderTrackingViewController: UIViewController, MKMapViewDelegate {
    private let viewModel: OrderTrackingViewModel
    private weak var router: AppRouting?
    private let scroll = UIScrollView()
    private let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.l)
    private let map = MKMapView()
    private let etaLabel = UILabel(font: DK.Font.rounded(28, .heavy, style: .title1), lines: 0)
    private let statusDetail = UILabel(font: DK.Font.body, color: DK.Color.textSecondary, lines: 0)
    private let liveBadge = PaddedLabel()
    private let demoBadge = PaddedLabel()
    private let progress = OrderProgressView()
    private let detailsStack = UIStackView(axis: .vertical, spacing: DK.Spacing.s)
    private let actionsStack = UIStackView(axis: .vertical, spacing: DK.Spacing.s)
    private let riderAnnotation = MKPointAnnotation()
    private var hasFramedMap = false

    init(viewModel: OrderTrackingViewModel, router: AppRouting) {
        self.viewModel = viewModel
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Track order"
        view.backgroundColor = DK.Color.background
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "orderTrackingScreen"

        map.delegate = self
        map.layer.cornerRadius = DK.Radius.l
        map.isRotateEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.heightAnchor.constraint(equalToConstant: 220).isActive = true
        map.accessibilityLabel = "Delivery map"
        riderAnnotation.title = "Rider (simulated)"

        for (badge, text, color) in [(liveBadge, "● LIVE", DK.Color.success), (demoBadge, "DEMO TRACKING · simulated rider", DK.Color.warning)] {
            badge.text = text
            badge.font = DK.Font.captionBold
            badge.textColor = color
            badge.backgroundColor = color.withAlphaComponent(0.12)
            badge.layer.cornerRadius = 6
            badge.layer.masksToBounds = true
        }
        etaLabel.accessibilityIdentifier = "trackingStatus"
        let badges = UIStackView(axis: .horizontal, spacing: DK.Spacing.s, arrangedSubviews: [liveBadge, demoBadge, UIView()])
        let header = UIStackView(axis: .vertical, spacing: DK.Spacing.xs, arrangedSubviews: [badges, etaLabel, statusDetail])
        [header, map, CardView(content: progress), CardView(content: detailsStack), actionsStack].forEach(stack.addArrangedSubview)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self] _ in Task { await self?.viewModel.refresh(); self?.scroll.refreshControl?.endRefreshing() } }, for: .valueChanged)
        scroll.refreshControl = refresh
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: DK.Spacing.l),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: DK.Spacing.page),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -DK.Spacing.page),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -DK.Spacing.xxl),
        ])

        viewModel.onChange = { [weak self] in self?.render() }
        viewModel.onLiveStatus = { [weak self] status in
            Haptics.success()
            self?.toast(status.title, style: .success)
        }
        installOverlay(SkeletonListView(rows: 3))
        viewModel.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true { viewModel.stop() }
    }

    private func render() {
        guard let order = viewModel.order else {
            if let error = viewModel.error {
                installOverlay(makeStateView(for: error) { [weak self] in Task { await self?.viewModel.refresh() } })
            }
            return
        }
        installOverlay(nil)
        let status = viewModel.status
        if status == .cancelled {
            etaLabel.text = "Order cancelled"
        } else if status == .delivered {
            etaLabel.text = "Delivered 🎉"
        } else if status == .pendingPayment {
            etaLabel.text = "Awaiting payment"
        } else {
            etaLabel.text = viewModel.minutesRemaining.map { "Arriving in ~\($0) min" } ?? status.title
        }
        statusDetail.text = status == .cancelled ? (order.cancelReason ?? status.detail) : status.detail
        liveBadge.isHidden = !viewModel.isLive || status.isFinal
        demoBadge.isHidden = !order.isDemoTracking || status.isFinal
        progress.configure(current: status, timeline: order.timeline)
        renderMap()
        renderDetails(order)
        renderActions(order)
    }

    // MARK: Map

    private func renderMap() {
        guard let tracking = viewModel.tracking else { map.isHidden = true; return }
        guard let destination = tracking.destination else {
            // Fallback: no coordinates for this order → timeline only.
            map.isHidden = true
            return
        }
        map.isHidden = viewModel.status.isFinal
        let cafe = CLLocationCoordinate2D(latitude: tracking.cafeLocation.latitude, longitude: tracking.cafeLocation.longitude)
        let home = CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude)
        if map.annotations.isEmpty {
            let cafePin = MKPointAnnotation()
            cafePin.coordinate = cafe
            cafePin.title = viewModel.order?.cafe?.name ?? "Café"
            let homePin = MKPointAnnotation()
            homePin.coordinate = home
            homePin.title = "You"
            map.addAnnotations([cafePin, homePin])
            map.addOverlay(MKPolyline(coordinates: [cafe, home], count: 2))
        }
        if let rider = viewModel.rider, viewModel.status == .outForDelivery {
            UIView.animate(withDuration: 0.8) {
                self.riderAnnotation.coordinate = CLLocationCoordinate2D(latitude: rider.latitude, longitude: rider.longitude)
            }
            if !map.annotations.contains(where: { $0 === riderAnnotation }) { map.addAnnotation(riderAnnotation) }
        }
        if !hasFramedMap {
            hasFramedMap = true
            let rect = MKMapRect(origin: MKMapPoint(cafe), size: .init(width: 0, height: 0)).union(MKMapRect(origin: MKMapPoint(home), size: .init(width: 0, height: 0)))
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50), animated: false)
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = MKPolylineRenderer(overlay: overlay)
        renderer.strokeColor = DK.Color.primary.withAlphaComponent(0.7)
        renderer.lineWidth = 4
        renderer.lineDashPattern = [6, 6]
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
        if annotation === riderAnnotation {
            view.glyphImage = UIImage(systemName: "bicycle")
            view.markerTintColor = DK.Color.warning
        } else if annotation.title == "You" {
            view.glyphImage = UIImage(systemName: "house.fill")
            view.markerTintColor = DK.Color.success
        } else {
            view.glyphImage = UIImage(systemName: "cup.and.saucer.fill")
            view.markerTintColor = DK.Color.primary
        }
        return view
    }

    // MARK: Details

    private func renderDetails(_ order: OrderDetail) {
        detailsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let title = UILabel(font: DK.Font.headline, text: "\(order.cafe?.name ?? "Order") · \(order.orderNumber)")
        detailsStack.addArrangedSubview(title)
        detailsStack.addArrangedSubview(UILabel(font: DK.Font.caption, color: DK.Color.textSecondary, lines: 0, text: "Placed \(order.createdAt.orderDateText)"))
        for item in order.items {
            let options = item.options.map(\.name).joined(separator: ", ")
            let name = UILabel(font: DK.Font.body, lines: 0, text: "\(item.quantity) × \(item.name)\(options.isEmpty ? "" : "\n   \(options)")")
            let price = UILabel(font: DK.Font.price, text: Money.format(item.lineTotalPaise))
            price.setContentHuggingPriority(.required, for: .horizontal)
            detailsStack.addArrangedSubview(UIStackView(axis: .horizontal, spacing: DK.Spacing.s, alignment: .firstBaseline, arrangedSubviews: [name, price]))
        }
        let bill = BillView()
        bill.configure(order.bill, couponCode: order.couponCode)
        detailsStack.addArrangedSubview(bill)
        if let address = order.deliveryAddress {
            detailsStack.addArrangedSubview(UILabel(font: DK.Font.caption, color: DK.Color.textSecondary, lines: 0, text: "Delivering to: \(address.text)"))
        }
        if let payment = order.latestPayment {
            let text: String
            switch payment.status {
            case .refunded: text = "Refund of \(Money.format(payment.amountPaise)) initiated — usually 5–7 business days (instant for demo payments)."
            case .succeeded: text = "Paid via \(payment.provider == .mock ? "demo payment" : payment.provider == .razorpay ? "Razorpay" : "cash")."
            case .pending where payment.provider == .cashOnDelivery: text = "Pay \(Money.format(payment.amountPaise)) in cash on delivery."
            case .failed, .cancelled: text = "Payment \(payment.status.rawValue.lowercased())\(payment.failureReason.map { ": \($0)" } ?? "")."
            default: text = "Payment \(payment.status.rawValue.lowercased())."
            }
            detailsStack.addArrangedSubview(UILabel(font: DK.Font.caption, color: payment.status == .refunded ? DK.Color.success : DK.Color.textSecondary, lines: 0, text: text))
        }
    }

    private func renderActions(_ order: OrderDetail) {
        actionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if order.canReview {
            let rate = QBButton(title: "Rate this order", image: UIImage(systemName: "star.fill"))
            rate.addAction(UIAction { [weak self] _ in
                self?.router?.showWriteReview(orderId: order.id, cafeName: order.cafe?.name ?? "the café") { Task { await self?.viewModel.refresh() } }
            }, for: .touchUpInside)
            actionsStack.addArrangedSubview(rate)
        }
        if order.status.isFinal {
            let reorder = QBButton(title: "Reorder", style: .outline, image: UIImage(systemName: "arrow.clockwise"))
            reorder.addAction(UIAction { [weak self] _ in self?.reorderTapped() }, for: .touchUpInside)
            actionsStack.addArrangedSubview(reorder)
        }
        if let phone = order.cafe?.phone, !order.status.isFinal {
            let call = QBButton(title: "Call the café", style: .outline, image: UIImage(systemName: "phone.fill"))
            call.addAction(UIAction { _ in
                if let url = URL(string: "tel://\(phone)") { UIApplication.shared.open(url) }
            }, for: .touchUpInside)
            actionsStack.addArrangedSubview(call)
        }
        let help = QBButton(title: "Help & support", style: .text, image: UIImage(systemName: "questionmark.circle"))
        help.addAction(UIAction { _ in
            if let url = URL(string: "mailto:support@quickbite.app?subject=Order%20\(order.orderNumber)") { UIApplication.shared.open(url) }
        }, for: .touchUpInside)
        actionsStack.addArrangedSubview(help)
        if order.canCancel {
            let cancel = QBButton(title: "Cancel order", style: .text)
            cancel.accessibilityIdentifier = "cancelOrderButton"
            cancel.addAction(UIAction { [weak self] _ in self?.cancelTapped() }, for: .touchUpInside)
            actionsStack.addArrangedSubview(cancel)
        }
    }

    private func cancelTapped() {
        confirm(title: "Cancel this order?", message: "You can cancel until the café starts preparing. Paid orders are refunded.", confirmTitle: "Cancel order", destructive: true) { [weak self] in
            Task {
                do {
                    try await self?.viewModel.cancel(reason: "Cancelled from the app")
                    self?.toast("Order cancelled")
                } catch {
                    self?.showError(error, title: "Couldn't cancel")
                }
            }
        }
    }

    private func reorderTapped() {
        Task {
            do {
                let skipped = try await viewModel.reorder()
                if !skipped.isEmpty { toast("Unavailable now: \(skipped.joined(separator: ", "))", style: .info) }
                router?.showCart()
            } catch {
                showError(error, title: "Couldn't reorder")
            }
        }
    }
}

/// Vertical step tracker: Order placed → … → Delivered.
final class OrderProgressView: UIView {
    private let stack = UIStackView(axis: .vertical, spacing: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        stack.pinEdges(to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(current: OrderStatus, timeline: [TimelineEvent]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if current == .cancelled || current == .pendingPayment {
            let row = UILabel(font: DK.Font.bodyBold, color: current == .cancelled ? DK.Color.error : DK.Color.warning, lines: 0, text: "\(current.title) — \(current.detail)")
            stack.addArrangedSubview(row)
            return
        }
        let currentIndex = current.stepIndex ?? 0
        let times = Dictionary(timeline.map { ($0.status, $0.at) }, uniquingKeysWith: { first, _ in first })
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        for (index, step) in OrderStatus.trackingSteps.enumerated() {
            let done = index <= currentIndex
            let isCurrent = index == currentIndex && current != .delivered
            let dot = UIImageView(image: UIImage(systemName: done ? (isCurrent ? step.symbol : "checkmark.circle.fill") : "circle"))
            dot.tintColor = done ? (isCurrent ? DK.Color.primary : DK.Color.success) : DK.Color.separator
            dot.contentMode = .scaleAspectFit
            dot.translatesAutoresizingMaskIntoConstraints = false
            let line = UIView()
            line.backgroundColor = index < currentIndex ? DK.Color.success : DK.Color.separator
            line.translatesAutoresizingMaskIntoConstraints = false
            line.isHidden = index == OrderStatus.trackingSteps.count - 1
            let rail = UIView()
            rail.translatesAutoresizingMaskIntoConstraints = false
            rail.addSubview(dot)
            rail.addSubview(line)
            let title = UILabel(font: isCurrent ? DK.Font.headline : DK.Font.body, color: done ? DK.Color.textPrimary : DK.Color.textTertiary, text: step.title)
            let time = UILabel(font: DK.Font.caption, color: DK.Color.textTertiary, text: times[step].map { formatter.string(from: $0) } ?? (isCurrent ? "In progress" : ""))
            let text = UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [title, time])
            let row = UIStackView(axis: .horizontal, spacing: DK.Spacing.m, alignment: .top, arrangedSubviews: [rail, text])
            row.isAccessibilityElement = true
            row.accessibilityLabel = "\(step.title), \(done ? (isCurrent ? "in progress" : "done") : "pending")"
            NSLayoutConstraint.activate([
                rail.widthAnchor.constraint(equalToConstant: 24),
                rail.heightAnchor.constraint(equalToConstant: 52),
                dot.topAnchor.constraint(equalTo: rail.topAnchor),
                dot.centerXAnchor.constraint(equalTo: rail.centerXAnchor),
                dot.widthAnchor.constraint(equalToConstant: 22),
                dot.heightAnchor.constraint(equalToConstant: 22),
                line.topAnchor.constraint(equalTo: dot.bottomAnchor, constant: 2),
                line.bottomAnchor.constraint(equalTo: rail.bottomAnchor),
                line.centerXAnchor.constraint(equalTo: rail.centerXAnchor),
                line.widthAnchor.constraint(equalToConstant: 2),
            ])
            stack.addArrangedSubview(row)
        }
    }
}
