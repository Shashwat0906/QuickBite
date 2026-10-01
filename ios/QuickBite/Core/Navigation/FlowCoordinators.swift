import UIKit

/// Modal sign-in / sign-up flow. Reports `true` when the user ends up signed in.
@MainActor
final class AuthCoordinator: Coordinator {
    var children: [Coordinator] = []
    var onFinish: ((Bool) -> Void)?
    private let env: AppEnvironment
    private let reason: String
    private let nav = UINavigationController()

    init(env: AppEnvironment, reason: String) {
        self.env = env
        self.reason = reason
    }

    func start() {}

    func start(presentingFrom presenter: UIViewController) {
        let login = LoginViewController(viewModel: LoginViewModel(env: env), reason: reason)
        login.onSignedIn = { [weak self] in self?.finish(true) }
        login.onCreateAccount = { [weak self] in self?.showSignup() }
        login.onClose = { [weak self] in self?.finish(false) }
        nav.viewControllers = [login]
        nav.modalPresentationStyle = .fullScreen
        presenter.present(nav, animated: true)
    }

    private func showSignup() {
        let signup = SignupViewController(viewModel: SignupViewModel(env: env))
        signup.onSignedIn = { [weak self] in self?.finish(true) }
        nav.pushViewController(signup, animated: true)
    }

    private func finish(_ signedIn: Bool) {
        nav.dismiss(animated: true) { [weak self] in self?.onFinish?(signedIn) }
    }
}

/// Cart → checkout → payment → confirmation, presented modally.
/// Finishes with the placed order's id (or nil if the user backed out).
@MainActor
final class CheckoutCoordinator: Coordinator {
    var children: [Coordinator] = []
    var onFinish: ((String?) -> Void)?
    private let env: AppEnvironment
    private weak var router: AppRouting?
    private let nav = UINavigationController()

    init(env: AppEnvironment, router: AppRouting) {
        self.env = env
        self.router = router
    }

    func start() {}

    func start(presentingFrom presenter: UIViewController) {
        let cart = CartViewController(viewModel: CartViewModel(env: env))
        cart.onCheckout = { [weak self] in self?.proceedToCheckout() }
        cart.onClose = { [weak self] in self?.finish(nil) }
        cart.onBrowse = { [weak self] in self?.finish(nil) }
        nav.viewControllers = [cart]
        presenter.present(nav, animated: true)
    }

    private func proceedToCheckout() {
        guard let router else { return }
        router.requireSignIn(reason: "Sign in to place your order") { [weak self] in
            guard let self else { return }
            let checkout = CheckoutViewController(viewModel: CheckoutViewModel(env: self.env))
            checkout.onOrderPlaced = { [weak self] order in self?.showConfirmation(order) }
            checkout.onAddAddress = { [weak self, weak checkout] in
                guard let self else { return }
                let form = AddressFormViewController(env: self.env, existing: nil)
                form.onSaved = { address in checkout?.select(address: address) }
                self.nav.pushViewController(form, animated: true)
            }
            self.nav.pushViewController(checkout, animated: true)
        }
    }

    private func showConfirmation(_ order: OrderDetail) {
        // Ask for push permission at a meaningful moment (skipped in UI tests: the system alert would block them).
        if !env.config.isUITesting { env.push.requestPermissionIfNeeded() }
        let done = OrderPlacedViewController(order: order)
        done.onTrack = { [weak self] in self?.finish(order.id) }
        nav.setViewControllers([done], animated: true)
    }

    private func finish(_ orderId: String?) {
        nav.dismiss(animated: true) { [weak self] in self?.onFinish?(orderId) }
    }
}
