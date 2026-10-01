import UIKit
import DesignKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

/// Tiny bridge so files that don't import DesignKit (AppDelegate) can use tokens.
enum DKBridge {
    static var background: UIColor { DK.Color.background }
    static var surface: UIColor { DK.Color.surface }
    static var primary: UIColor { DK.Color.primary }
    static var textPrimary: UIColor { DK.Color.textPrimary }
    static var headline: UIFont { DK.Font.headline }
    static var largeTitle: UIFont { DK.Font.largeTitle }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene,
              let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let window = UIWindow(windowScene: windowScene)
        window.tintColor = DK.Color.primary
        let styles: [UIUserInterfaceStyle] = [.unspecified, .light, .dark]
        window.overrideUserInterfaceStyle = styles[min(2, max(0, UserDefaults.standard.integer(forKey: "qb.appearance")))]
        self.window = window
        let coordinator = AppCoordinator(window: window, environment: appDelegate.environment)
        appCoordinator = coordinator
        coordinator.start()
        if let url = connectionOptions.urlContexts.first?.url { handle(url) }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        handle(url)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        appCoordinator?.sceneDidBecomeActive()
    }

    /// quickbite://order/<id> deep links, and Google Sign-In's OAuth callback.
    private func handle(_ url: URL) {
        #if canImport(GoogleSignIn)
        if GIDSignIn.sharedInstance.handle(url) { return }
        #endif
        if url.scheme == "quickbite", url.host == "order", let id = url.pathComponents.dropFirst().first {
            appCoordinator?.openOrder(id: id)
        }
    }
}
