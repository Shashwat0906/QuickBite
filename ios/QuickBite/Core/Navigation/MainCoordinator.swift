import UIKit
import DesignKit

/// Owns the tab bar and every "browse" navigation. Screens call into it through
/// `AppRouting`; it pushes onto whichever tab is currently visible.
@MainActor
final class MainCoordinator: Coordinator, AppRouting {
    var children: [Coordinator] = []
    let tabBarController: MainTabBarController
    private let env: AppEnvironment

    private let homeNav = UINavigationController()
    private let searchNav = UINavigationController()
    private let ordersNav = UINavigationController()
    private let profileNav = UINavigationController()

    init(environment: AppEnvironment) {
        self.env = environment
        self.tabBarController = MainTabBarController(cart: environment.cart)
    }

    func start() {
        let home = HomeViewController(viewModel: HomeViewModel(env: env), router: self)
        homeNav.viewControllers = [home]
        homeNav.tabBarItem = UITabBarItem(title: "Home", image: UIImage(systemName: "house"), selectedImage: UIImage(systemName: "house.fill"))
        homeNav.tabBarItem.accessibilityIdentifier = "tab_home"

        let search = SearchViewController(viewModel: SearchViewModel(env: env), router: self)
        searchNav.viewControllers = [search]
        searchNav.tabBarItem = UITabBarItem(title: "Search", image: UIImage(systemName: "magnifyingglass"), selectedImage: UIImage(systemName: "magnifyingglass"))
        searchNav.tabBarItem.accessibilityIdentifier = "tab_search"

        let orders = OrdersViewController(viewModel: OrdersViewModel(env: env), router: self)
        ordersNav.viewControllers = [orders]
        ordersNav.tabBarItem = UITabBarItem(title: "Orders", image: UIImage(systemName: "bag"), selectedImage: UIImage(systemName: "bag.fill"))
        ordersNav.tabBarItem.accessibilityIdentifier = "tab_orders"

        let profile = ProfileViewController(env: env, router: self)
        profileNav.viewControllers = [profile]
        profileNav.tabBarItem = UITabBarItem(title: "Profile", image: UIImage(systemName: "person.crop.circle"), selectedImage: UIImage(systemName: "person.crop.circle.fill"))
        profileNav.tabBarItem.accessibilityIdentifier = "tab_profile"

        [homeNav, searchNav, ordersNav, profileNav].forEach { $0.navigationBar.prefersLargeTitles = false }
        tabBarController.viewControllers = [homeNav, searchNav, ordersNav, profileNav]
        tabBarController.onCartTapped = { [weak self] in self?.showCart() }
    }

    private var currentNav: UINavigationController {
        (tabBarController.selectedViewController as? UINavigationController) ?? homeNav
    }

    private var topPresenter: UIViewController {
        var top: UIViewController = tabBarController
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    // MARK: AppRouting

    func showCafe(id: String) {
        let vc = CafeDetailViewController(viewModel: CafeDetailViewModel(cafeId: id, env: env), router: self)
        currentNav.pushViewController(vc, animated: true)
    }

    func showCafeList(title: String, category: String?) {
        let vc = CafeListViewController(viewModel: CafeListViewModel(title: title, category: category, env: env), router: self)
        currentNav.pushViewController(vc, animated: true)
    }

    func showSearch(query: String?) {
        tabBarController.selectedViewController = searchNav
        searchNav.popToRootViewController(animated: false)
        (searchNav.viewControllers.first as? SearchViewController)?.startSearch(query: query)
    }

    func showCart() {
        let checkout = CheckoutCoordinator(env: env, router: self)
        checkout.onFinish = { [weak self, weak checkout] placedOrderId in
            guard let self, let checkout else { return }
            self.removeChild(checkout)
            if let placedOrderId { self.showOrder(id: placedOrderId) }
        }
        addChild(checkout)
        checkout.start(presentingFrom: topPresenter)
    }

    func showOrder(id: String) {
        if tabBarController.presentedViewController != nil { tabBarController.dismiss(animated: false) }
        tabBarController.selectedViewController = ordersNav
        ordersNav.popToRootViewController(animated: false)
        let vc = OrderTrackingViewController(viewModel: OrderTrackingViewModel(orderId: id, env: env), router: self)
        ordersNav.pushViewController(vc, animated: true)
    }

    func showOrdersTab() {
        tabBarController.selectedViewController = ordersNav
    }

    func showWriteReview(orderId: String, cafeName: String, onDone: (() -> Void)?) {
        let vc = WriteReviewViewController(viewModel: WriteReviewViewModel(orderId: orderId, cafeName: cafeName, service: env.reviews))
        vc.onSubmitted = onDone
        let nav = UINavigationController(rootViewController: vc)
        if let sheet = nav.sheetPresentationController { sheet.detents = [.large()] }
        topPresenter.present(nav, animated: true)
    }

    func showCafeReviews(cafe: Cafe) {
        currentNav.pushViewController(ReviewsListViewController(mode: .cafe(cafe), service: env.reviews), animated: true)
    }

    func showLocationPicker() {
        let picker = LocationPickerViewController(env: env, router: self)
        let nav = UINavigationController(rootViewController: picker)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        topPresenter.present(nav, animated: true)
    }

    func showEditProfile() {
        profileNav.pushViewController(EditProfileViewController(env: env), animated: true)
    }

    func showAddresses() {
        currentNav.pushViewController(AddressesViewController(env: env, mode: .manage), animated: true)
    }

    func showPaymentPreferences() {
        profileNav.pushViewController(PaymentPreferencesViewController(env: env), animated: true)
    }

    func showNotificationSettings() {
        profileNav.pushViewController(NotificationSettingsViewController(env: env), animated: true)
    }

    func showNotificationsInbox() {
        let vc = NotificationsInboxViewController(env: env)
        vc.onOpenOrder = { [weak self] id in self?.showOrder(id: id) }
        currentNav.pushViewController(vc, animated: true)
    }

    func showMyReviews() {
        profileNav.pushViewController(ReviewsListViewController(mode: .mine, service: env.reviews), animated: true)
    }

    func showServerSettings() {
        profileNav.pushViewController(ServerSettingsViewController(env: env), animated: true)
    }

    func requireSignIn(reason: String, then action: @escaping () -> Void) {
        if env.session.isSignedIn { action(); return }
        let auth = AuthCoordinator(env: env, reason: reason)
        auth.onFinish = { [weak self, weak auth] signedIn in
            guard let self, let auth else { return }
            self.removeChild(auth)
            if signedIn { action() }
        }
        addChild(auth)
        auth.start(presentingFrom: topPresenter)
    }

    func signOut() {
        Task {
            await env.signOut()
            env.cart.clear()
            ToastView.show("You've been signed out.", style: .success, in: tabBarController.view)
        }
    }
}

/// Tab bar with a floating "View cart" bar above it (like quick-commerce apps).
final class MainTabBarController: UITabBarController {
    var onCartTapped: (() -> Void)?
    private let cart: CartStore
    private let cartBar = CartBarView()
    private var cartObserver: NSObjectProtocol?

    init(cart: CartStore) {
        self.cart = cart
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(cartBar)
        cartBar.addAction(UIAction { [weak self] _ in self?.onCartTapped?() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            cartBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DK.Spacing.page),
            cartBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DK.Spacing.page),
            cartBar.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -DK.Spacing.s),
        ])
        cartObserver = NotificationCenter.default.addObserver(forName: .cartDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshCartBar(animated: true) }
        }
        refreshCartBar(animated: false)
    }

    deinit {
        if let cartObserver { NotificationCenter.default.removeObserver(cartObserver) }
    }

    private func refreshCartBar(animated: Bool) {
        let visible = !cart.isEmpty
        cartBar.configure(itemCount: cart.itemCount, total: cart.estimate.subtotalPaise, cafeName: cart.cafe?.name)
        let inset: CGFloat = visible ? 72 : 0
        viewControllers?.forEach { $0.additionalSafeAreaInsets.bottom = inset }
        let changes = {
            self.cartBar.alpha = visible ? 1 : 0
            self.cartBar.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 24)
        }
        if animated {
            UIView.animate(withDuration: DK.Motion.standard, delay: 0, usingSpringWithDamping: DK.Motion.spring.damping, initialSpringVelocity: 0, animations: changes)
        } else {
            changes()
        }
        cartBar.isUserInteractionEnabled = visible
    }
}

/// "2 items | ₹378 · View cart ›" bar.
final class CartBarView: UIControl {
    private let countLabel = UILabel(font: DK.Font.captionBold, color: UIColor.white.withAlphaComponent(0.9))
    private let totalLabel = UILabel(font: DK.Font.headline, color: .white)
    private let actionLabel = UILabel(font: DK.Font.headline, color: .white, text: "View cart")

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = DK.Color.primary
        layer.cornerRadius = DK.Radius.m
        applyCardShadow(opacity: 0.25, radius: 12, y: 6)
        let left = UIStackView(axis: .vertical, spacing: 0, arrangedSubviews: [countLabel, totalLabel])
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .white
        let right = UIStackView(axis: .horizontal, spacing: DK.Spacing.xs, alignment: .center, arrangedSubviews: [actionLabel, chevron])
        let row = UIStackView(axis: .horizontal, spacing: DK.Spacing.m, alignment: .center, arrangedSubviews: [left, UIView(), right])
        row.isUserInteractionEnabled = false
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 10, left: DK.Spacing.l, bottom: 10, right: DK.Spacing.l))
        heightAnchor.constraint(equalToConstant: 60).isActive = true
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "viewCartBar"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(itemCount: Int, total: Paise, cafeName: String?) {
        countLabel.text = "\(itemCount) item\(itemCount == 1 ? "" : "s")\(cafeName.map { " · \($0)" } ?? "")"
        totalLabel.text = Money.format(total)
        accessibilityLabel = "View cart, \(itemCount) items, \(Money.spoken(total))"
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.85 : 1 }
    }
}
