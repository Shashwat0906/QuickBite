import UIKit
import DesignKit

/// Cart: lines with steppers, edit customisation, coupon, bill, checkout.
final class CartViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onCheckout: (() -> Void)?
    var onClose: (() -> Void)?
    var onBrowse: (() -> Void)?

    private let viewModel: CartViewModel
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let footer = UIView()
    private let checkoutButton = QBButton(title: "Proceed to checkout")
    private let totalLabel = UILabel(font: DK.Font.headline)
    private let estimateLabel = UILabel(font: DK.Font.caption, color: DK.Color.textSecondary)
    private let couponField = UITextField()
    private let billView = BillView()
    private var display: CartViewModel.Display?

    private enum Section: Int, CaseIterable { case issues, items, coupon, bill }

    init(viewModel: CartViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Your cart"
        view.backgroundColor = DK.Color.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.onClose?() })
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Clear", primaryAction: UIAction { [weak self] _ in
            self?.confirm(title: "Clear cart?", message: "This removes every item from your cart.", confirmTitle: "Clear", destructive: true) { self?.viewModel.clear() }
        })

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = DK.Color.background
        tableView.accessibilityIdentifier = "cartTable"
        tableView.register(CartLineCell.self, forCellReuseIdentifier: CartLineCell.reuseID)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "plain")
        tableView.keyboardDismissMode = .onDrag
        tableView.translatesAutoresizingMaskIntoConstraints = false

        checkoutButton.accessibilityIdentifier = "checkoutButton"
        checkoutButton.addAction(UIAction { [weak self] _ in self?.onCheckout?() }, for: .touchUpInside)
        totalLabel.accessibilityIdentifier = "cartTotal"
        let totals = UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [totalLabel, estimateLabel])
        let row = UIStackView(axis: .horizontal, spacing: DK.Spacing.l, alignment: .center, arrangedSubviews: [totals, checkoutButton])
        totals.setContentHuggingPriority(.required, for: .horizontal)
        footer.backgroundColor = DK.Color.surface
        footer.applyCardShadow(opacity: 0.08, radius: 10, y: -2)
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableView)
        view.addSubview(footer)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            row.topAnchor.constraint(equalTo: footer.topAnchor, constant: DK.Spacing.m),
            row.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: DK.Spacing.page),
            row.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -DK.Spacing.page),
            row.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DK.Spacing.s),
        ])

        viewModel.onChange = { [weak self] display in self?.render(display) }
        viewModel.refresh()
    }

    private func render(_ display: CartViewModel.Display) {
        self.display = display
        if display.lines.isEmpty {
            footer.isHidden = true
            navigationItem.rightBarButtonItem?.isEnabled = false
            let empty = StateView(.empty(symbol: "cart", title: "Your cart is empty", message: "Add something delicious from a café near you."), actionTitle: "Browse cafés") { [weak self] in
                self?.onBrowse?()
            }
            installOverlay(empty)
            return
        }
        installOverlay(nil)
        footer.isHidden = false
        navigationItem.rightBarButtonItem?.isEnabled = true
        totalLabel.text = Money.format(display.bill.totalPaise)
        estimateLabel.text = display.isSyncing ? "Updating prices…" : (display.isEstimate ? "Estimated total" : "Total incl. taxes")
        checkoutButton.isEnabled = display.canCheckout || !viewModel.isSignedIn
        checkoutButton.setTitle(viewModel.isSignedIn ? "Proceed to checkout" : "Sign in to checkout")
        billView.configure(display.bill, isEstimate: display.isEstimate, couponCode: display.coupon?.isValid == true ? display.coupon?.code : nil)
        tableView.reloadData()
    }

    // MARK: Table

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let display else { return 0 }
        switch Section(rawValue: section)! {
        case .issues: return display.issues.count + (display.freeDeliveryHint == nil ? 0 : 1)
        case .items: return display.lines.count
        case .coupon: return 1
        case .bill: return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .items: return display?.cafeName.map { "From \($0)" }
        case .coupon: return "Offers & coupons"
        case .bill: return "Bill details"
        case .issues: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let display else { return UITableViewCell() }
        switch Section(rawValue: indexPath.section)! {
        case .issues:
            let cell = tableView.dequeueReusableCell(withIdentifier: "plain", for: indexPath)
            var content = cell.defaultContentConfiguration()
            if indexPath.row < display.issues.count {
                content.text = display.issues[indexPath.row].message
                content.image = UIImage(systemName: "exclamationmark.triangle.fill")
                content.imageProperties.tintColor = DK.Color.warning
            } else {
                content.text = display.freeDeliveryHint
                content.image = UIImage(systemName: "bicycle")
                content.imageProperties.tintColor = DK.Color.success
            }
            content.textProperties.font = DK.Font.callout
            content.textProperties.numberOfLines = 0
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            return cell
        case .items:
            let line = display.lines[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: CartLineCell.reuseID, for: indexPath) as! CartLineCell
            cell.configure(line, issue: viewModel.issue(for: line)?.message)
            cell.onQuantity = { [weak self] value in self?.viewModel.setQuantity(value, for: line) }
            cell.onEdit = { [weak self] in self?.edit(line) }
            return cell
        case .coupon:
            let cell = tableView.dequeueReusableCell(withIdentifier: "plain", for: indexPath)
            cell.contentConfiguration = nil
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            cell.selectionStyle = .none
            let row = makeCouponRow(display)
            cell.contentView.addSubview(row)
            row.pinEdges(to: cell.contentView)
            return cell
        case .bill:
            let cell = tableView.dequeueReusableCell(withIdentifier: "plain", for: indexPath)
            cell.contentConfiguration = nil
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            cell.selectionStyle = .none
            cell.contentView.addSubview(billView)
            billView.pinEdges(to: cell.contentView, insets: UIEdgeInsets(top: DK.Spacing.m, left: DK.Spacing.l, bottom: DK.Spacing.m, right: DK.Spacing.l))
            return cell
        }
    }

    private func makeCouponRow(_ display: CartViewModel.Display) -> UIView {
        let container = UIStackView(axis: .vertical, spacing: DK.Spacing.s)
        if let code = display.couponCode {
            let status: String
            let color: UIColor
            if let coupon = display.coupon {
                status = coupon.isValid ? "✓ \(coupon.code) applied — you save \(Money.format(coupon.discountPaise))" : "✗ \(coupon.message)"
                color = coupon.isValid ? DK.Color.success : DK.Color.error
            } else {
                status = viewModel.isSignedIn ? "Checking \(code)…" : "\(code) will be applied after you sign in"
                color = DK.Color.textSecondary
            }
            let label = UILabel(font: DK.Font.callout, color: color, lines: 0, text: status)
            label.accessibilityIdentifier = "couponStatus"
            let remove = UIButton(type: .system)
            remove.setTitle("Remove", for: .normal)
            remove.addAction(UIAction { [weak self] _ in self?.viewModel.applyCoupon(nil) }, for: .touchUpInside)
            remove.setContentHuggingPriority(.required, for: .horizontal)
            container.addArrangedSubview(UIStackView(axis: .horizontal, spacing: DK.Spacing.s, alignment: .center, arrangedSubviews: [label, remove]))
        } else {
            couponField.placeholder = "Enter coupon code (e.g. WELCOME50)"
            couponField.autocapitalizationType = .allCharacters
            couponField.autocorrectionType = .no
            couponField.font = DK.Font.body
            couponField.text = nil
            couponField.accessibilityIdentifier = "couponField"
            let apply = UIButton(type: .system)
            apply.setTitle("Apply", for: .normal)
            apply.titleLabel?.font = DK.Font.bodyBold
            apply.accessibilityIdentifier = "applyCoupon"
            apply.addAction(UIAction { [weak self] _ in
                guard let self, let code = self.couponField.text, !code.isEmpty else { return }
                self.view.endEditing(true)
                self.viewModel.applyCoupon(code)
            }, for: .touchUpInside)
            apply.setContentHuggingPriority(.required, for: .horizontal)
            let icon = UIImageView(image: UIImage(systemName: "ticket"))
            icon.tintColor = DK.Color.primary
            container.addArrangedSubview(UIStackView(axis: .horizontal, spacing: DK.Spacing.m, alignment: .center, arrangedSubviews: [icon, couponField, apply]))
        }
        container.isLayoutMarginsRelativeArrangement = true
        container.directionalLayoutMargins = .init(top: DK.Spacing.m, leading: DK.Spacing.l, bottom: DK.Spacing.m, trailing: DK.Spacing.l)
        return container
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .items, let line = display?.lines[safe: indexPath.row] else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, done in
            self?.viewModel.remove(line)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private func edit(_ line: CartLine) {
        guard line.menuItem.isCustomizable else { return }
        let sheet = ItemCustomizationViewController(viewModel: ItemCustomizationViewModel(item: line.menuItem, preselected: line.optionIds, quantity: line.quantity), confirmTitle: "Update")
        sheet.onConfirm = { [weak self] optionIds, quantity in self?.viewModel.updateOptions(optionIds, quantity: quantity, for: line) }
        let nav = UINavigationController(rootViewController: sheet)
        nav.sheetPresentationController?.detents = [.medium(), .large()]
        present(nav, animated: true)
    }
}

final class CartLineCell: UITableViewCell {
    static let reuseID = "CartLineCell"
    var onQuantity: ((Int) -> Void)?
    var onEdit: (() -> Void)?

    private let diet = DietIndicator()
    private let nameLabel = UILabel(font: DK.Font.bodyBold, lines: 2)
    private let optionsLabel = UILabel(font: DK.Font.caption, color: DK.Color.textSecondary, lines: 2)
    private let editButton = UIButton(type: .system)
    private let issueLabel = UILabel(font: DK.Font.caption, color: DK.Color.error, lines: 0)
    private let priceLabel = UILabel(font: DK.Font.price)
    private let stepper = QuantityStepper()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        editButton.setTitle("Edit ›", for: .normal)
        editButton.titleLabel?.font = DK.Font.captionBold
        editButton.contentHorizontalAlignment = .leading
        editButton.addAction(UIAction { [weak self] _ in self?.onEdit?() }, for: .touchUpInside)
        stepper.onChange = { [weak self] value in self?.onQuantity?(value) }
        priceLabel.textAlignment = .right

        let titleRow = UIStackView(axis: .horizontal, spacing: DK.Spacing.xs, alignment: .firstBaseline, arrangedSubviews: [diet, nameLabel])
        let text = UIStackView(axis: .vertical, spacing: 2, alignment: .leading, arrangedSubviews: [titleRow, optionsLabel, editButton, issueLabel])
        let right = UIStackView(axis: .vertical, spacing: DK.Spacing.s, alignment: .trailing, arrangedSubviews: [stepper, priceLabel])
        right.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(axis: .horizontal, spacing: DK.Spacing.m, alignment: .top, arrangedSubviews: [text, right])
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: UIEdgeInsets(top: DK.Spacing.m, left: DK.Spacing.l, bottom: DK.Spacing.m, right: DK.Spacing.l))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ line: CartLine, issue: String?) {
        diet.set(DietIndicator.Diet(rawValue: line.menuItem.diet.rawValue) ?? .veg)
        nameLabel.text = line.menuItem.name
        optionsLabel.text = line.optionsSummary
        optionsLabel.isHidden = line.optionsSummary == nil
        editButton.isHidden = !line.menuItem.isCustomizable
        issueLabel.text = issue
        issueLabel.isHidden = issue == nil
        priceLabel.text = Money.format(line.lineTotalPaise)
        stepper.setValue(line.quantity)
        stepper.accessibilityIdentifier = "cartStepper_\(line.menuItem.name)"
        accessibilityIdentifier = "cartLine_\(line.menuItem.name)"
    }
}

/// Checkout: address, payment method, bill, place order + payment handling.
final class CheckoutViewController: UIViewController {
    var onOrderPlaced: ((OrderDetail) -> Void)?
    var onAddAddress: (() -> Void)?

    private let viewModel: CheckoutViewModel
    private let scroll = UIScrollView()
    private let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.l)
    private let placeButton = QBButton(title: "Place order")
    private let billView = BillView()
    private let issueLabel = UILabel(font: DK.Font.callout, color: DK.Color.error, lines: 0)
    private lazy var razorpay = RazorpayCheckoutPresenter()

    init(viewModel: CheckoutViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Checkout"
        view.backgroundColor = DK.Color.background
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        placeButton.accessibilityIdentifier = "placeOrderButton"
        placeButton.addAction(UIAction { [weak self] _ in self?.placeOrderTapped() }, for: .touchUpInside)
        view.addSubview(placeButton)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: placeButton.topAnchor, constant: -DK.Spacing.s),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: DK.Spacing.l),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: DK.Spacing.page),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -DK.Spacing.page),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -DK.Spacing.l),
            placeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DK.Spacing.page),
            placeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DK.Spacing.page),
            placeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DK.Spacing.s),
        ])
        viewModel.onChange = { [weak self] in self?.render() }
        installOverlay(SkeletonListView(rows: 3, imageSize: 44))
        Task { await viewModel.load() }
    }

    /// Called after the user adds a new address.
    func select(address: Address) { viewModel.select(address: address) }

    private func render() {
        if viewModel.isLoading && viewModel.pricedCart == nil { return }
        if let error = viewModel.loadError {
            installOverlay(StateView(.error(title: "Couldn't start checkout", message: error), actionTitle: "Try again") { [weak self] in
                Task { await self?.viewModel.load() }
            })
            return
        }
        installOverlay(nil)
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.addArrangedSubview(sectionTitle("Deliver to"))
        stack.addArrangedSubview(addressCard())
        stack.addArrangedSubview(sectionTitle("Order summary"))
        stack.addArrangedSubview(summaryCard())
        stack.addArrangedSubview(sectionTitle("Pay with"))
        stack.addArrangedSubview(paymentCard())
        stack.addArrangedSubview(sectionTitle("Bill details"))
        if let bill = viewModel.bill {
            billView.configure(bill, couponCode: viewModel.pricedCart?.coupon?.isValid == true ? viewModel.pricedCart?.coupon?.code : nil)
            stack.addArrangedSubview(CardView(content: billView))
        }
        issueLabel.text = viewModel.blockingIssue
        issueLabel.isHidden = viewModel.blockingIssue == nil
        stack.addArrangedSubview(issueLabel)
        let note = UILabel(font: DK.Font.caption, color: DK.Color.textTertiary, lines: 0, text: "Prices were re-checked with the café just now. Card details are handled by the payment provider and never stored by QuickBite.")
        stack.addArrangedSubview(note)
        placeButton.setTitle(viewModel.placeButtonTitle)
        placeButton.isEnabled = viewModel.canPlaceOrder
        placeButton.isLoading = viewModel.isPlacing
    }

    private func sectionTitle(_ text: String) -> UILabel {
        let label = UILabel(font: DK.Font.headline, text: text)
        label.accessibilityTraits = .header
        return label
    }

    private func addressCard() -> UIView {
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.s)
        if viewModel.addresses.isEmpty {
            stack.addArrangedSubview(UILabel(font: DK.Font.body, color: DK.Color.textSecondary, lines: 0, text: "Add an address to continue."))
        }
        for address in viewModel.addresses {
            let selected = address == viewModel.selectedAddress
            var config = UIButton.Configuration.plain()
            config.title = "\(address.label)"
            config.subtitle = address.fullText
            config.image = UIImage(systemName: selected ? "largecircle.fill.circle" : "circle")?.withTintColor(selected ? DK.Color.primary : DK.Color.textTertiary, renderingMode: .alwaysOriginal)
            config.imagePadding = DK.Spacing.m
            config.titleAlignment = .leading
            config.baseForegroundColor = DK.Color.textPrimary
            let button = UIButton(configuration: config)
            button.contentHorizontalAlignment = .leading
            button.tintColor = DK.Color.primary
            button.accessibilityIdentifier = "address_\(address.label)"
            button.addAction(UIAction { [weak self] _ in self?.viewModel.select(address: address) }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        let add = QBButton(title: "Add new address", style: .text, image: UIImage(systemName: "plus.circle"))
        add.accessibilityIdentifier = "addAddress"
        add.addAction(UIAction { [weak self] _ in self?.onAddAddress?() }, for: .touchUpInside)
        stack.addArrangedSubview(add)
        return CardView(content: stack)
    }

    private func summaryCard() -> UIView {
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.s)
        if let cafe = viewModel.pricedCart?.cafe {
            stack.addArrangedSubview(UILabel(font: DK.Font.bodyBold, text: cafe.name))
        }
        for line in viewModel.pricedCart?.lines ?? [] {
            let name = UILabel(font: DK.Font.body, lines: 0, text: "\(line.quantity) × \(line.menuItem.name)")
            let price = UILabel(font: DK.Font.price, text: Money.format(line.lineTotalPaise))
            price.setContentHuggingPriority(.required, for: .horizontal)
            stack.addArrangedSubview(UIStackView(axis: .horizontal, spacing: DK.Spacing.s, alignment: .firstBaseline, arrangedSubviews: [name, price]))
        }
        return CardView(content: stack)
    }

    private func paymentCard() -> UIView {
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.s)
        for method in viewModel.methods {
            let selected = method.id == viewModel.selectedMethodId
            var config = UIButton.Configuration.plain()
            config.title = method.title + (method.isMock ? "  (DEMO)" : "")
            config.subtitle = method.subtitle
            config.image = UIImage(systemName: selected ? "largecircle.fill.circle" : "circle")?.withTintColor(selected ? DK.Color.primary : DK.Color.textTertiary, renderingMode: .alwaysOriginal)
            config.imagePadding = DK.Spacing.m
            config.titleAlignment = .leading
            config.baseForegroundColor = DK.Color.textPrimary
            let button = UIButton(configuration: config)
            button.contentHorizontalAlignment = .leading
            button.tintColor = DK.Color.primary
            button.accessibilityIdentifier = "payment_\(method.id)"
            button.addAction(UIAction { [weak self] _ in self?.viewModel.select(methodId: method.id) }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        return CardView(content: stack)
    }

    // MARK: Ordering & payment

    private func placeOrderTapped() {
        Task {
            do {
                let step = try await viewModel.placeOrder()
                handle(step)
            } catch {
                Haptics.error()
                showError(error, title: "Couldn't place order")
            }
        }
    }

    private func handle(_ step: CheckoutViewModel.PaymentStep) {
        switch step {
        case .done(let order):
            Haptics.success()
            onOrderPlaced?(order)
        case .mock(let payment, let order):
            let sheet = MockPaymentViewController(amount: payment.amountPaise, orderNumber: order.orderNumber)
            sheet.onOutcome = { [weak self] outcome in self?.finishMock(payment: payment, order: order, outcome: outcome) }
            let nav = UINavigationController(rootViewController: sheet)
            nav.isModalInPresentation = true
            nav.sheetPresentationController?.detents = [.medium()]
            present(nav, animated: true)
        case .razorpay(let payment, let order):
            razorpay.present(from: self, payment: payment, order: order, user: viewModel.session.user) { [weak self] result in
                self?.finishRazorpay(result, payment: payment, order: order)
            }
        }
    }

    private func finishMock(payment: PaymentInfo, order: OrderDetail, outcome: String) {
        Task {
            do {
                let updated = try await viewModel.completeMockPayment(payment, outcome: outcome)
                if updated.status == .pendingPayment {
                    paymentFailed(order: updated, message: outcome == "cancel" ? "Payment was cancelled." : "The demo payment was declined.")
                } else {
                    Haptics.success()
                    onOrderPlaced?(updated)
                }
            } catch {
                paymentFailed(order: order, message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func finishRazorpay(_ result: RazorpayCheckoutPresenter.Result, payment: PaymentInfo, order: OrderDetail) {
        Task {
            switch result {
            case let .success(paymentId, orderId, signature):
                do {
                    let updated = try await viewModel.verifyRazorpay(payment, paymentId: paymentId, orderId: orderId, signature: signature)
                    Haptics.success()
                    onOrderPlaced?(updated)
                } catch {
                    paymentFailed(order: order, message: (error as? LocalizedError)?.errorDescription ?? "We couldn't verify the payment.")
                }
            case .cancelled:
                await viewModel.reportPaymentFailure(payment, cancelled: true, reason: nil)
                paymentFailed(order: order, message: "Payment was cancelled.")
            case .failed(let message):
                await viewModel.reportPaymentFailure(payment, cancelled: false, reason: message)
                paymentFailed(order: order, message: message)
            }
        }
    }

    /// Retry or cancel. The order is kept as "awaiting payment" meanwhile.
    private func paymentFailed(order: OrderDetail, message: String) {
        Haptics.error()
        let alert = UIAlertController(title: "Payment not completed", message: "\(message)\nYour order \(order.orderNumber) is saved — you can try paying again.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Try again", style: .default) { [weak self] _ in
            guard let self else { return }
            Task {
                do { self.handle(try await self.viewModel.retryPayment(order: order)) } catch { self.showError(error) }
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel order", style: .destructive) { [weak self] _ in
            Task {
                await self?.viewModel.cancelUnpaidOrder(order)
                self?.navigationController?.dismiss(animated: true)
            }
        })
        present(alert, animated: true)
    }
}

/// Clearly labelled demo payment sheet (no real money moves).
final class MockPaymentViewController: UIViewController {
    var onOutcome: ((String) -> Void)?
    private let amount: Paise
    private let orderNumber: String

    init(amount: Paise, orderNumber: String) {
        self.amount = amount
        self.orderNumber = orderNumber
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Demo payment"
        view.backgroundColor = DK.Color.background
        let badge = PaddedLabel()
        badge.text = "DEMO MODE · NO REAL MONEY"
        badge.font = DK.Font.captionBold
        badge.textColor = DK.Color.warning
        badge.backgroundColor = DK.Color.warning.withAlphaComponent(0.14)
        badge.layer.cornerRadius = 6
        badge.layer.masksToBounds = true
        badge.insets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        let amountLabel = UILabel(font: DK.Font.largeTitle, text: Money.format(amount))
        let detail = UILabel(font: DK.Font.callout, color: DK.Color.textSecondary, lines: 0, text: "Order \(orderNumber). This simulates a payment gateway so the full flow can be demonstrated without Razorpay keys.")
        detail.textAlignment = .center
        let pay = QBButton(title: "Simulate successful payment")
        pay.accessibilityIdentifier = "mockPaySuccess"
        let fail = QBButton(title: "Simulate failure", style: .outline)
        fail.accessibilityIdentifier = "mockPayFailure"
        let cancel = QBButton(title: "Cancel", style: .text)
        pay.addAction(UIAction { [weak self] _ in self?.finish("success") }, for: .touchUpInside)
        fail.addAction(UIAction { [weak self] _ in self?.finish("failure") }, for: .touchUpInside)
        cancel.addAction(UIAction { [weak self] _ in self?.finish("cancel") }, for: .touchUpInside)
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.m, alignment: .center, arrangedSubviews: [badge, amountLabel, detail, pay, fail, cancel])
        [pay, fail, cancel].forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DK.Spacing.l),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DK.Spacing.xxl),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DK.Spacing.xxl),
        ])
    }

    private func finish(_ outcome: String) {
        dismiss(animated: true) { [weak self] in self?.onOutcome?(outcome) }
    }
}

/// Success screen with a little celebration, then "Track order".
final class OrderPlacedViewController: UIViewController {
    var onTrack: (() -> Void)?
    private let order: OrderDetail

    init(order: OrderDetail) {
        self.order = order
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DK.Color.background
        navigationItem.hidesBackButton = true
        let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 88, weight: .bold)))
        check.tintColor = DK.Color.success
        let title = UILabel(font: DK.Font.largeTitle, lines: 0, text: "Order placed!")
        title.textAlignment = .center
        title.accessibilityIdentifier = "orderPlacedTitle"
        let detail = UILabel(font: DK.Font.body, color: DK.Color.textSecondary, lines: 0,
                             text: "\(order.orderNumber) · \(Money.format(order.totalPaise))\n\(order.cafe?.name ?? "The café") is getting it ready. Arriving in about \(order.estimatedMinutes) minutes.")
        detail.textAlignment = .center
        let track = QBButton(title: "Track order", image: UIImage(systemName: "location.fill"))
        track.accessibilityIdentifier = "trackOrderButton"
        track.addAction(UIAction { [weak self] _ in self?.onTrack?() }, for: .touchUpInside)
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.l, alignment: .center, arrangedSubviews: [check, title, detail, track])
        stack.setCustomSpacing(DK.Spacing.xxxl, after: detail)
        track.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DK.Spacing.xxl),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DK.Spacing.xxl),
        ])
        check.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        check.alpha = 0
        UIView.animate(withDuration: 0.6, delay: 0.1, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8) {
            check.transform = .identity
            check.alpha = 1
        }
        Haptics.success()
    }
}
