import Foundation
import NetworkKit

/// Client-side validation rules. They mirror the API's rules so users get
/// instant feedback, but the server validates again (never trust the client).
enum AuthValidator {
    static func email(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Enter your email" }
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return trimmed.range(of: pattern, options: .regularExpression) == nil ? "Enter a valid email address" : nil
    }

    static func password(_ value: String, isNew: Bool) -> String? {
        if value.isEmpty { return "Enter your password" }
        guard isNew else { return nil }
        if value.count < 8 { return "Use at least 8 characters" }
        if value.rangeOfCharacter(from: .letters) == nil { return "Add at least one letter" }
        if value.rangeOfCharacter(from: .decimalDigits) == nil { return "Add at least one number" }
        return nil
    }

    static func name(_ value: String) -> String? {
        value.trimmingCharacters(in: .whitespaces).count < 2 ? "Enter your name" : nil
    }

    /// Optional; when present must be 10–13 digits with an optional leading +.
    static func phone(_ value: String) -> String? {
        let trimmed = value.replacingOccurrences(of: " ", with: "")
        if trimmed.isEmpty { return nil }
        return trimmed.range(of: #"^\+?[0-9]{10,13}$"#, options: .regularExpression) == nil ? "Enter a valid phone number" : nil
    }

    /// 0…4 strength meter for the sign-up screen.
    static func strength(_ password: String) -> Int {
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil && password.rangeOfCharacter(from: .letters) != nil { score += 1 }
        if password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { score += 1 }
        return score
    }
}

struct LoginFieldErrors: Equatable {
    var email: String?
    var password: String?
    var isValid: Bool { email == nil && password == nil }
}

@MainActor
final class LoginViewModel {
    enum State: Equatable {
        case idle
        case loading
        case failed(String)
        case signedIn
    }

    private let auth: AuthServicing
    private let persistSession: (User, AuthTokens) -> Void
    let isGoogleConfigured: Bool
    private(set) var state: State = .idle { didSet { onStateChange?(state) } }
    var onStateChange: ((State) -> Void)?
    /// True when the server accepted a demo social token (shown to the user).
    private(set) var lastSignInWasDemo = false

    init(auth: AuthServicing, isGoogleConfigured: Bool, persistSession: @escaping (User, AuthTokens) -> Void) {
        self.auth = auth
        self.isGoogleConfigured = isGoogleConfigured
        self.persistSession = persistSession
    }

    convenience init(env: AppEnvironment) {
        self.init(auth: env.auth, isGoogleConfigured: env.config.isGoogleSignInConfigured) { [weak env] user, tokens in
            env?.session.signIn(user: user, tokens: tokens)
            env?.push.syncTokenWithBackend()
        }
    }

    func validate(email: String, password: String) -> LoginFieldErrors {
        LoginFieldErrors(email: AuthValidator.email(email), password: AuthValidator.password(password, isNew: false))
    }

    /// Returns field errors (and doesn't call the API) when the form is invalid.
    @discardableResult
    func login(email: String, password: String) async -> LoginFieldErrors {
        let errors = validate(email: email, password: password)
        guard errors.isValid, state != .loading else { return errors }
        state = .loading
        do {
            let response = try await auth.login(email: email.trimmingCharacters(in: .whitespaces).lowercased(), password: password)
            persistSession(response.user, response.tokens)
            state = .signedIn
        } catch {
            state = .failed((error as? APIError)?.userMessage ?? error.localizedDescription)
        }
        return errors
    }

    func socialLogin(provider: String, identityToken: String, name: String?) async {
        guard state != .loading else { return }
        state = .loading
        do {
            let response = try await auth.socialLogin(provider: provider, identityToken: identityToken, name: name)
            lastSignInWasDemo = response.isDemo ?? false
            persistSession(response.user, response.tokens)
            state = .signedIn
        } catch {
            state = .failed((error as? APIError)?.userMessage ?? error.localizedDescription)
        }
    }

    func resetError() {
        if case .failed = state { state = .idle }
    }
}

struct SignupFieldErrors: Equatable {
    var name: String?
    var email: String?
    var phone: String?
    var password: String?
    var confirm: String?
    var isValid: Bool { [name, email, phone, password, confirm].allSatisfy { $0 == nil } }
}

@MainActor
final class SignupViewModel {
    typealias State = LoginViewModel.State

    private let auth: AuthServicing
    private let persistSession: (User, AuthTokens) -> Void
    private(set) var state: State = .idle { didSet { onStateChange?(state) } }
    var onStateChange: ((State) -> Void)?

    init(auth: AuthServicing, persistSession: @escaping (User, AuthTokens) -> Void) {
        self.auth = auth
        self.persistSession = persistSession
    }

    convenience init(env: AppEnvironment) {
        self.init(auth: env.auth) { [weak env] user, tokens in
            env?.session.signIn(user: user, tokens: tokens)
            env?.push.syncTokenWithBackend()
        }
    }

    func validate(name: String, email: String, phone: String, password: String, confirm: String) -> SignupFieldErrors {
        SignupFieldErrors(
            name: AuthValidator.name(name),
            email: AuthValidator.email(email),
            phone: AuthValidator.phone(phone),
            password: AuthValidator.password(password, isNew: true),
            confirm: confirm == password ? nil : "Passwords don't match"
        )
    }

    @discardableResult
    func signUp(name: String, email: String, phone: String, password: String, confirm: String) async -> SignupFieldErrors {
        let errors = validate(name: name, email: email, phone: phone, password: password, confirm: confirm)
        guard errors.isValid, state != .loading else { return errors }
        state = .loading
        do {
            let cleanPhone = phone.replacingOccurrences(of: " ", with: "")
            let response = try await auth.register(
                name: name.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                password: password,
                phone: cleanPhone.isEmpty ? nil : cleanPhone
            )
            persistSession(response.user, response.tokens)
            state = .signedIn
        } catch {
            state = .failed((error as? APIError)?.userMessage ?? error.localizedDescription)
        }
        return errors
    }
}
