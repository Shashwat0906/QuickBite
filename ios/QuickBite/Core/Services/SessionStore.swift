import Foundation
import NetworkKit

extension Notification.Name {
    /// Posted on the main queue whenever the user signs in, signs out or their profile changes.
    static let sessionDidChange = Notification.Name("QuickBite.sessionDidChange")
}

/// Owns the signed-in user and their tokens.
///
/// - Tokens live in the Keychain; the user profile is cached alongside them.
/// - Implements `AuthTokenProvider` so NetworkKit can attach and refresh tokens.
/// - Refreshes are single-flight: if five requests hit a 401 together, only one
///   refresh call is made and all five wait for it.
final class SessionStore: AuthTokenProvider, @unchecked Sendable {
    private let keychain: KeychainStore
    private let refreshClient: APIClient
    private let lock = NSLock()
    private var tokens: AuthTokens?
    private var refreshTask: Task<String?, Error>?
    private(set) var user: User?

    var isSignedIn: Bool { lock.withLock { tokens != nil } }

    /// - Parameter refreshClient: a client *without* a token provider (used only for /auth/refresh).
    init(keychain: KeychainStore = KeychainStore(), refreshClient: APIClient) {
        self.keychain = keychain
        self.refreshClient = refreshClient
        self.tokens = keychain.value(AuthTokens.self, for: "tokens")
        self.user = keychain.value(User.self, for: "user")
    }

    func signIn(user: User, tokens: AuthTokens) {
        lock.withLock {
            self.user = user
            self.tokens = tokens
        }
        keychain.set(tokens, for: "tokens")
        keychain.set(user, for: "user")
        notify()
    }

    func update(user: User) {
        lock.withLock { self.user = user }
        keychain.set(user, for: "user")
        notify()
    }

    func signOut() {
        lock.withLock {
            user = nil
            tokens = nil
            refreshTask?.cancel()
            refreshTask = nil
        }
        keychain.remove("tokens")
        keychain.remove("user")
        notify()
    }

    var refreshToken: String? { lock.withLock { tokens?.refreshToken } }

    // MARK: AuthTokenProvider

    func accessToken() async -> String? {
        lock.withLock { tokens?.accessToken }
    }

    func refreshAccessToken() async throws -> String? {
        let task: Task<String?, Error> = lock.withLock {
            if let running = refreshTask { return running }
            let refresh = tokens?.refreshToken
            let task = Task<String?, Error> { [weak self] in
                guard let self, let refresh else { return nil }
                defer { self.lock.withLock { self.refreshTask = nil } }
                do {
                    let endpoint = try Endpoint<TokensResponse>(path: "/auth/refresh", method: .post, jsonBody: ["refreshToken": refresh])
                    let response = try await self.refreshClient.send(endpoint)
                    self.lock.withLock { self.tokens = response.tokens }
                    self.keychain.set(response.tokens, for: "tokens")
                    return response.tokens.accessToken
                } catch let error as APIError where error.statusCode == 401 {
                    // Refresh token expired or revoked → the user must sign in again.
                    self.signOut()
                    return nil
                }
            }
            refreshTask = task
            return task
        }
        return try await task.value
    }

    private func notify() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: .sessionDidChange, object: self) }
    }
}
