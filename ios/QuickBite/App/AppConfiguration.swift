import Foundation

/// Runtime configuration: API URL, launch-argument switches for tests, and
/// which optional integrations are configured.
struct AppConfiguration {
    static let baseURLOverrideKey = "qb.apiBaseURLOverride"

    /// Launched by UI tests: use the in-process stub server, reset state.
    let isUITesting: Bool
    let resetState: Bool
    let skipOnboarding: Bool
    let apiBaseURL: URL
    let googleClientID: String?

    static func current(processInfo: ProcessInfo = .processInfo, bundle: Bundle = .main, defaults: UserDefaults = .standard) -> AppConfiguration {
        let args = processInfo.arguments
        let isUITesting = args.contains("-uiTesting")
        let plistURL = (bundle.object(forInfoDictionaryKey: "API_BASE_URL") as? String).flatMap(URL.init(string:))
        let override = defaults.string(forKey: baseURLOverrideKey).flatMap(URL.init(string:))
        let fallback = URL(string: "http://localhost:4000")!
        let base = isUITesting ? URL(string: "https://stub.quickbite.test")! : (override ?? plistURL ?? fallback)
        let googleID = (bundle.object(forInfoDictionaryKey: "GIDClientID") as? String).flatMap { $0.isEmpty ? nil : $0 }
        return AppConfiguration(
            isUITesting: isUITesting,
            resetState: args.contains("-resetState"),
            skipOnboarding: args.contains("-skipOnboarding"),
            apiBaseURL: base,
            googleClientID: googleID
        )
    }

    /// REST root, e.g. https://host/api/v1
    var apiV1URL: URL { apiBaseURL.appendingPathComponent("api/v1") }
    var isGoogleSignInConfigured: Bool { googleClientID != nil }
}
