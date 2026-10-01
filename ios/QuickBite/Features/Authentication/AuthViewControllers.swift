import UIKit
import AuthenticationServices
import DesignKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

/// Email/password login + Sign in with Apple + Google Sign-In.
final class LoginViewController: UIViewController, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    var onSignedIn: (() -> Void)?
    var onCreateAccount: (() -> Void)?
    var onClose: (() -> Void)?

    private let viewModel: LoginViewModel
    private let reason: String
    private let scrollView = UIScrollView()
    private let emailField = QBTextField(title: "Email", placeholder: "you@example.com", keyboard: .emailAddress, contentType: .username)
    private let passwordField = QBTextField(title: "Password", placeholder: "Your password", isSecure: true, contentType: .password)
    private let loginButton = QBButton(title: "Sign in")
    private let errorLabel = UILabel(font: DK.Font.callout, color: DK.Color.error, lines: 0)
    private let appleButton = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
    private let googleButton = QBButton(title: "Continue with Google", style: .outline, image: UIImage(systemName: "g.circle.fill"))

    init(viewModel: LoginViewModel, reason: String) {
        self.viewModel = viewModel
        self.reason = reason
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DK.Color.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.onClose?() })
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "closeLogin"
        buildLayout()
        bind()
    }

    private func buildLayout() {
        let title = UILabel(font: DK.Font.largeTitle, lines: 0, text: "Welcome back 👋")
        title.accessibilityTraits = .header
        let subtitle = UILabel(font: DK.Font.body, color: DK.Color.textSecondary, lines: 0, text: reason)

        emailField.textField.accessibilityIdentifier = "loginEmail"
        passwordField.textField.accessibilityIdentifier = "loginPassword"
        loginButton.accessibilityIdentifier = "loginButton"
        errorLabel.accessibilityIdentifier = "loginError"
        errorLabel.isHidden = true
        emailField.onReturn = { [weak self] in self?.passwordField.textField.becomeFirstResponder() }
        passwordField.onReturn = { [weak self] in self?.submit() }
        emailField.onChange = { [weak self] _ in self?.viewModel.resetError() }
        passwordField.onChange = { [weak self] _ in self?.viewModel.resetError() }
        loginButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)

        let divider = makeDivider()
        appleButton.cornerRadius = DK.Radius.m
        appleButton.translatesAutoresizingMaskIntoConstraints = false
        appleButton.addAction(UIAction { [weak self] _ in self?.startAppleSignIn() }, for: .touchUpInside)
        appleButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        googleButton.addAction(UIAction { [weak self] _ in self?.startGoogleSignIn() }, for: .touchUpInside)

        let signupRow = UIStackView(axis: .horizontal, spacing: DK.Spacing.xs, alignment: .center)
        let newLabel = UILabel(font: DK.Font.body, color: DK.Color.textSecondary, text: "New to QuickBite?")
        let signup = UIButton(type: .system)
        signup.setTitle("Create an account", for: .normal)
        signup.titleLabel?.font = DK.Font.bodyBold
        signup.accessibilityIdentifier = "goToSignup"
        signup.addAction(UIAction { [weak self] _ in self?.onCreateAccount?() }, for: .touchUpInside)
        [newLabel, signup].forEach(signupRow.addArrangedSubview)

        let demoHint = UILabel(font: DK.Font.caption, color: DK.Color.textTertiary, lines: 0, text: "Demo account: demo@quickbite.app · Demo@1234")
        demoHint.textAlignment = .center

        let centeredSignup = UIStackView(axis: .vertical, alignment: .center, arrangedSubviews: [signupRow])
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.l, arrangedSubviews: [
            title, subtitle, emailField, passwordField, errorLabel, loginButton, divider, appleButton, googleButton, centeredSignup, demoHint,
        ])
        stack.setCustomSpacing(DK.Spacing.xs, after: title)
        stack.setCustomSpacing(DK.Spacing.xxl, after: subtitle)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: DK.Spacing.xl),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: DK.Spacing.xxl),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -DK.Spacing.xxl),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -DK.Spacing.xl),
        ])
    }

    private func makeDivider() -> UIView {
        let left = UIView(), right = UIView()
        [left, right].forEach {
            $0.backgroundColor = DK.Color.separator
            $0.heightAnchor.constraint(equalToConstant: 1).isActive = true
        }
        let label = UILabel(font: DK.Font.caption, color: DK.Color.textTertiary, text: "or")
        label.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(axis: .horizontal, spacing: DK.Spacing.m, alignment: .center, arrangedSubviews: [left, label, right])
        left.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        return row
    }

    private func bind() {
        viewModel.onStateChange = { [weak self] state in
            guard let self else { return }
            self.loginButton.isLoading = state == .loading
            switch state {
            case .failed(let message):
                self.errorLabel.text = message
                self.errorLabel.isHidden = false
                Haptics.error()
            case .signedIn:
                Haptics.success()
                if self.viewModel.lastSignInWasDemo {
                    self.toast("Signed in with a demo social account")
                }
                self.onSignedIn?()
            default:
                self.errorLabel.isHidden = true
            }
        }
    }

    private func submit() {
        view.endEditing(true)
        Task {
            let errors = await viewModel.login(email: emailField.text, password: passwordField.text)
            emailField.errorMessage = errors.email
            passwordField.errorMessage = errors.password
        }
    }

    // MARK: Sign in with Apple

    private func startAppleSignIn() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
            showError(NSError(domain: "QuickBite", code: 1, userInfo: [NSLocalizedDescriptionKey: "Apple didn't return an identity token."]))
            return
        }
        let name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
        Task { await viewModel.socialLogin(provider: "APPLE", identityToken: token, name: name.isEmpty ? nil : name) }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let code = (error as? ASAuthorizationError)?.code
        if code == .canceled { return }
        // Typical on a simulator / build without the Apple capability: offer the labelled demo flow.
        offerDemoSignIn(provider: "APPLE", reason: "Sign in with Apple isn't available in this build (\(error.localizedDescription)).")
    }

    // MARK: Google

    private func startGoogleSignIn() {
        #if canImport(GoogleSignIn)
        if viewModel.isGoogleConfigured {
            GIDSignIn.sharedInstance.signIn(withPresenting: self) { [weak self] result, error in
                guard let self else { return }
                if let error = error as? GIDSignInError, error.code == .canceled { return }
                guard let token = result?.user.idToken?.tokenString else {
                    if let error { self.showError(error) }
                    return
                }
                let name = result?.user.profile?.name
                Task { await self.viewModel.socialLogin(provider: "GOOGLE", identityToken: token, name: name) }
            }
            return
        }
        #endif
        offerDemoSignIn(provider: "GOOGLE", reason: "Google Sign-In needs a client ID (see README → Google Sign-In).")
    }

    /// Clearly labelled demo path: the server accepts "demo:<email>" only when
    /// SOCIAL_LOGIN_DEMO=true, so this can't bypass real auth in production.
    private func offerDemoSignIn(provider: String, reason: String) {
        let alert = UIAlertController(title: "Use a demo account?", message: "\(reason)\n\nYou can continue with a demo \(provider.capitalized) sign-in for testing.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Email for the demo account"
            field.keyboardType = .emailAddress
            field.autocapitalizationType = .none
            field.text = "\(provider.lowercased())-demo@quickbite.app"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue (demo)", style: .default) { [weak self, weak alert] _ in
            let email = alert?.textFields?.first?.text ?? ""
            Task { await self?.viewModel.socialLogin(provider: provider, identityToken: "demo:\(email)", name: nil) }
        })
        present(alert, animated: true)
    }
}

/// Account creation with live validation and a password-strength meter.
final class SignupViewController: UIViewController {
    var onSignedIn: (() -> Void)?

    private let viewModel: SignupViewModel
    private let nameField = QBTextField(title: "Full name", placeholder: "Aarav Sharma", contentType: .name)
    private let emailField = QBTextField(title: "Email", placeholder: "you@example.com", keyboard: .emailAddress, contentType: .emailAddress)
    private let phoneField = QBTextField(title: "Phone (optional)", placeholder: "+91 98xxxxxxxx", keyboard: .phonePad, contentType: .telephoneNumber)
    private let passwordField = QBTextField(title: "Password", placeholder: "At least 8 characters, a letter and a number", isSecure: true, contentType: .newPassword)
    private let confirmField = QBTextField(title: "Confirm password", placeholder: "Repeat your password", isSecure: true, contentType: .newPassword)
    private let strengthBar = UIProgressView(progressViewStyle: .bar)
    private let strengthLabel = UILabel(font: DK.Font.caption, color: DK.Color.textSecondary)
    private let errorLabel = UILabel(font: DK.Font.callout, color: DK.Color.error, lines: 0)
    private let submitButton = QBButton(title: "Create account")

    init(viewModel: SignupViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DK.Color.background
        title = "Create account"
        nameField.textField.accessibilityIdentifier = "signupName"
        emailField.textField.accessibilityIdentifier = "signupEmail"
        passwordField.textField.accessibilityIdentifier = "signupPassword"
        confirmField.textField.accessibilityIdentifier = "signupConfirm"
        submitButton.accessibilityIdentifier = "signupButton"
        errorLabel.isHidden = true

        strengthBar.trackTintColor = DK.Color.separator
        strengthBar.layer.cornerRadius = 2
        strengthBar.clipsToBounds = true
        passwordField.onChange = { [weak self] value in self?.updateStrength(value) }
        updateStrength("")

        let fields: [QBTextField] = [nameField, emailField, phoneField, passwordField, confirmField]
        for (index, field) in fields.enumerated() {
            field.onReturn = { [weak self] in
                if index + 1 < fields.count { fields[index + 1].textField.becomeFirstResponder() } else { self?.submit() }
            }
        }
        submitButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)

        let strengthRow = UIStackView(axis: .vertical, spacing: DK.Spacing.xs, arrangedSubviews: [strengthBar, strengthLabel])
        let terms = UILabel(font: DK.Font.caption, color: DK.Color.textTertiary, lines: 0, text: "By continuing you agree to QuickBite's Terms and Privacy Policy.")
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.l, arrangedSubviews: [nameField, emailField, phoneField, passwordField, strengthRow, confirmField, errorLabel, submitButton, terms])
        stack.setCustomSpacing(DK.Spacing.s, after: passwordField)

        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: DK.Spacing.l),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: DK.Spacing.xxl),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -DK.Spacing.xxl),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -DK.Spacing.xl),
            strengthBar.heightAnchor.constraint(equalToConstant: 4),
        ])

        viewModel.onStateChange = { [weak self] state in
            guard let self else { return }
            self.submitButton.isLoading = state == .loading
            switch state {
            case .failed(let message):
                self.errorLabel.text = message
                self.errorLabel.isHidden = false
                Haptics.error()
            case .signedIn:
                Haptics.success()
                self.onSignedIn?()
            default:
                self.errorLabel.isHidden = true
            }
        }
    }

    private func updateStrength(_ password: String) {
        let score = AuthValidator.strength(password)
        let labels = ["Too short", "Weak", "Okay", "Strong", "Very strong"]
        let colors = [DK.Color.error, DK.Color.error, DK.Color.warning, DK.Color.success, DK.Color.success]
        strengthBar.setProgress(Float(score) / 4, animated: true)
        strengthBar.progressTintColor = colors[score]
        strengthLabel.text = password.isEmpty ? "Use 8+ characters with letters and numbers" : "Strength: \(labels[score])"
    }

    private func submit() {
        view.endEditing(true)
        Task {
            let errors = await viewModel.signUp(name: nameField.text, email: emailField.text, phone: phoneField.text, password: passwordField.text, confirm: confirmField.text)
            nameField.errorMessage = errors.name
            emailField.errorMessage = errors.email
            phoneField.errorMessage = errors.phone
            passwordField.errorMessage = errors.password
            confirmField.errorMessage = errors.confirm
        }
    }
}
