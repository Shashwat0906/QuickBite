import UIKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    /// Created here so push registration callbacks have somewhere to go.
    private(set) lazy var environment = AppEnvironment(config: .current())

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        configureAppearance()
        if !environment.config.isUITesting {
            environment.push.configure(application: application)
        } else {
            UIView.setAnimationsEnabled(false)
        }
        #if canImport(GoogleSignIn)
        if let clientID = environment.config.googleClientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        #endif
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        environment.push.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected on the simulator without push entitlements; the in-app channel still works.
        print("Push registration unavailable: \(error.localizedDescription)")
    }

    /// Global UIKit appearance so every bar matches the design system.
    private func configureAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = DKBridge.background
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: DKBridge.textPrimary, .font: DKBridge.headline]
        nav.largeTitleTextAttributes = [.foregroundColor: DKBridge.textPrimary, .font: DKBridge.largeTitle]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = DKBridge.primary

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = DKBridge.surface
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = DKBridge.primary
    }
}
