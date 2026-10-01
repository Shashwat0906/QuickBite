import UIKit
import DesignKit

/// Root of the app: splash → onboarding (first launch) → main tabs.
@MainActor
final class AppCoordinator: Coordinator {
    var children: [Coordinator] = []
    private let window: UIWindow
    private let env: AppEnvironment
    private var main: MainCoordinator?
    private var pendingOrderId: String?
    private var realtimeObserver: UUID?

    init(window: UIWindow, environment: AppEnvironment) {
        self.window = window
        self.env = environment
        env.push.onOpenOrder = { [weak self] id in self?.openOrder(id: id) }
    }

    func start() {
        let splash = SplashViewController { [weak self] in self?.routeAfterSplash() }
        window.rootViewController = splash
        window.makeKeyAndVisible()
        observeRealtimeNotifications()
        NotificationCenter.default.addObserver(forName: .sessionDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sessionChanged() }
        }
    }

    private func routeAfterSplash() {
        if env.hasSeenOnboarding {
            showMain(animated: true)
        } else {
            let onboarding = OnboardingViewController(
                onSignIn: { [weak self] in self?.finishOnboarding(thenSignIn: true) },
                onGuest: { [weak self] in self?.finishOnboarding(thenSignIn: false) }
            )
            transition(to: onboarding)
        }
    }

    private func finishOnboarding(thenSignIn: Bool) {
        env.hasSeenOnboarding = true
        showMain(animated: true)
        guard thenSignIn else { return }
        // Present after the root-controller swap has finished.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.main?.requireSignIn(reason: "Sign in to order from cafes near you") {}
        }
    }

    private func showMain(animated: Bool) {
        let coordinator = MainCoordinator(environment: env)
        main = coordinator
        children = [coordinator]
        coordinator.start()
        transition(to: coordinator.tabBarController, animated: animated)
        sessionChanged()
        if let id = pendingOrderId {
            pendingOrderId = nil
            coordinator.showOrder(id: id)
        }
    }

    private func transition(to viewController: UIViewController, animated: Bool = true) {
        guard animated, window.rootViewController != nil else {
            window.rootViewController = viewController
            return
        }
        UIView.transition(with: window, duration: DK.Motion.standard, options: .transitionCrossDissolve) {
            self.window.rootViewController = viewController
        }
    }

    /// Opens an order from a push notification or deep link.
    func openOrder(id: String) {
        guard let main else { pendingOrderId = id; return }
        main.showOrder(id: id)
    }

    func sceneDidBecomeActive() {
        if env.session.isSignedIn && !env.config.isUITesting { env.realtime.connect() }
    }

    private func sessionChanged() {
        if env.session.isSignedIn {
            if !env.config.isUITesting { env.realtime.connect() }
            env.push.syncTokenWithBackend()
        } else {
            env.realtime.disconnect()
        }
    }

    /// In-app fallback for push: show a banner for realtime notifications.
    private func observeRealtimeNotifications() {
        realtimeObserver = env.realtime.observe { [weak self] event in
            guard let self, case let .notification(title, body, orderId) = event else { return }
            guard let view = self.window.rootViewController?.view else { return }
            ToastView.show(body, title: title, style: .info, in: view, duration: 4) { [weak self] in
                if let orderId { self?.openOrder(id: orderId) }
            }
        }
    }
}
