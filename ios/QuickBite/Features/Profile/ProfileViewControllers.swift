import UIKit
import UserNotifications
import DesignKit
import NetworkKit

/// Profile tab: account header + settings rows.
final class ProfileViewController: UITableViewController {
    private enum Row {
        case signIn, editProfile, addresses, payments, notificationSettings, inbox, reviews, appearance, server, about, logout, delete

        var title: String {
            switch self {
            case .signIn: return "Sign in or create account"
            case .editProfile: return "Edit profile"
            case .addresses: return "Saved addresses"
            case .payments: return "Payment preferences"
            case .notificationSettings: return "Notification settings"
            case .inbox: return "Notifications"
            case .reviews: return "My ratings & reviews"
            case .appearance: return "Appearance"
            case .server: return "Server & diagnostics"
            case .about: return "About QuickBite"
            case .logout: return "Log out"
            case .delete: return "Delete account"
            }
        }

        var symbol: String {
            switch self {
            case .signIn: return "person.crop.circle.badge.plus"
            case .editProfile: return "person.fill"
            case .addresses: return "house.fill"
            case .payments: return "creditcard.fill"
            case .notificationSettings: return "bell.badge.fill"
            case .inbox: return "tray.full.fill"
            case .reviews: return "star.bubble.fill"
            case .appearance: return "circle.lefthalf.filled"
            case .server: return "server.rack"
            case .about: return "info.circle.fill"
            case .logout: return "rectangle.portrait.and.arrow.right"
            case .delete: return "trash.fill"
            }
        }
    }

    private let env: AppEnvironment
    private weak var router: AppRouting?
    private var observer: NSObjectProtocol?

    private var sections: [[Row]] {
        if env.session.isSignedIn {
            return [[.editProfile, .addresses, .payments], [.inbox, .notificationSettings, .reviews], [.appearance, .server, .about], [.logout, .delete]]
        }
        return [[.signIn], [.appearance, .server, .about]]
    }

    init(env: AppEnvironment, router: AppRouting) {
        self.env = env
        self.router = router
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile"
        tableView.backgroundColor = DK.Color.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.accessibilityIdentifier = "profileTable"
        observer = NotificationCenter.default.addObserver(forName: .sessionDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
        if env.session.isSignedIn {
            Task { if let user = try? await env.auth.me() { env.session.update(user: user) } }
        }
    }

    private func reload() {
        tableView.tableHeaderView = makeHeader()
        tableView.reloadData()
    }

    private func makeHeader() -> UIView {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 120))
        let avatar = UILabel(font: DK.Font.rounded(28, .bold, style: .title1), color: .white)
        avatar.textAlignment = .center
        avatar.backgroundColor = DK.Color.primary
        avatar.layer.cornerRadius = 32
        avatar.layer.masksToBounds = true
        let user = env.session.user
        avatar.text = String(user?.name.prefix(1) ?? "☕").uppercased()
        let name = UILabel(font: DK.Font.title2, text: user?.name ?? "Hello, guest")
        name.accessibilityIdentifier = "profileName"
        let detail = UILabel(font: DK.Font.callout, color: DK.Color.textSecondary, lines: 2, text: user.map { [$0.email, $0.phone].compactMap { $0 }.joined(separator: "\n") } ?? "Sign in to order and track deliveries")
        let text = UIStackView(axis: .vertical, spacing: 2, arrangedSubviews: [name, detail])
        let row = UIStackView(axis: .horizontal, spacing: DK.Spacing.l, alignment: .center, arrangedSubviews: [avatar, text])
        header.addSubview(row)
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 64),
            avatar.heightAnchor.constraint(equalToConstant: 64),
            row.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: DK.Spacing.xl),
            row.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -DK.Spacing.xl),
            row.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
        return header
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section][indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = row.title
        content.image = UIImage(systemName: row.symbol)
        let destructive = row == .delete || row == .logout
        content.imageProperties.tintColor = destructive ? DK.Color.error : DK.Color.primary
        content.textProperties.color = destructive ? DK.Color.error : DK.Color.textPrimary
        if row == .appearance {
            content.secondaryText = ["System", "Light", "Dark"][UserDefaults.standard.integer(forKey: "qb.appearance")]
            content.prefersSideBySideTextAndSecondaryText = true
        }
        cell.contentConfiguration = content
        cell.accessoryType = destructive ? .none : .disclosureIndicator
        cell.accessibilityIdentifier = "profileRow_\(row)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section][indexPath.row] {
        case .signIn: router?.requireSignIn(reason: "Sign in to QuickBite") {}
        case .editProfile: router?.showEditProfile()
        case .addresses: router?.showAddresses()
        case .payments: router?.showPaymentPreferences()
        case .notificationSettings: router?.showNotificationSettings()
        case .inbox: router?.showNotificationsInbox()
        case .reviews: router?.showMyReviews()
        case .server: router?.showServerSettings()
        case .appearance: chooseAppearance()
        case .about: showAbout()
        case .logout:
            confirm(title: "Log out?", message: nil, confirmTitle: "Log out", destructive: true) { [weak self] in self?.router?.signOut() }
        case .delete: confirmDelete()
        }
    }

    private func chooseAppearance() {
        let sheet = UIAlertController(title: "Appearance", message: nil, preferredStyle: .actionSheet)
        for (index, name) in ["System", "Light", "Dark"].enumerated() {
            sheet.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                UserDefaults.standard.set(index, forKey: "qb.appearance")
                let styles: [UIUserInterfaceStyle] = [.unspecified, .light, .dark]
                self?.view.window?.overrideUserInterfaceStyle = styles[index]
                self?.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let alert = UIAlertController(title: "QuickBite \(version)", message: "A café ordering & 10-minute delivery demo built with Swift, UIKit, MVVM + Coordinators, Node.js, PostgreSQL and Socket.IO.\n\nPhotos: Unsplash.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// App Store guideline 5.1.1(v): accounts must be deletable in-app.
    private func confirmDelete() {
        let alert = UIAlertController(title: "Delete your account?", message: "Your profile, addresses and saved data will be permanently removed. Past orders are kept anonymously for accounting. This can't be undone.", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Type DELETE to confirm" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete account", style: .destructive) { [weak self, weak alert] _ in
            guard let self, alert?.textFields?.first?.text?.uppercased() == "DELETE" else {
                self?.toast("Type DELETE to confirm", style: .error)
                return
            }
            Task {
                do {
                    try await self.env.auth.deleteAccount()
                    self.env.session.signOut()
                    self.env.cart.clear()
                    self.toast("Your account was deleted")
                } catch {
                    self.showError(error, title: "Couldn't delete account")
                }
            }
        })
        present(alert, animated: true)
    }
}

/// Edit name / email / phone.
final class EditProfileViewController: UIViewController {
    private let env: AppEnvironment
    private let nameField = QBTextField(title: "Full name", placeholder: "Your name", contentType: .name)
    private let emailField = QBTextField(title: "Email", placeholder: "you@example.com", keyboard: .emailAddress, contentType: .emailAddress)
    private let phoneField = QBTextField(title: "Phone", placeholder: "+91 98xxxxxxxx", keyboard: .phonePad, contentType: .telephoneNumber)
    private let saveButton = QBButton(title: "Save changes")

    init(env: AppEnvironment) {
        self.env = env
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Edit profile"
        view.backgroundColor = DK.Color.background
        let user = env.session.user
        nameField.text = user?.name ?? ""
        emailField.text = user?.email ?? ""
        phoneField.text = user?.phone ?? ""
        emailField.textField.isEnabled = user?.authProvider == "EMAIL"
        saveButton.addAction(UIAction { [weak self] _ in self?.save() }, for: .touchUpInside)
        let note = UILabel(font: DK.Font.caption, color: DK.Color.textTertiary, lines: 0, text: user?.authProvider == "EMAIL" ? nil : "Your email is managed by \(user?.authProvider.capitalized ?? "your sign-in provider").")
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.l, arrangedSubviews: [nameField, emailField, phoneField, note, saveButton])
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DK.Spacing.xl),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DK.Spacing.xxl),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DK.Spacing.xxl),
        ])
    }

    private func save() {
        nameField.errorMessage = AuthValidator.name(nameField.text)
        emailField.errorMessage = AuthValidator.email(emailField.text)
        phoneField.errorMessage = AuthValidator.phone(phoneField.text)
        guard nameField.errorMessage == nil, emailField.errorMessage == nil, phoneField.errorMessage == nil else { return }
        saveButton.isLoading = true
        Task {
            defer { saveButton.isLoading = false }
            do {
                let phone = phoneField.text.replacingOccurrences(of: " ", with: "")
                let user = try await env.auth.updateProfile(name: nameField.text, email: emailField.textField.isEnabled ? emailField.text.lowercased() : nil, phone: phone.isEmpty ? nil : phone)
                env.session.update(user: user)
                toast("Profile updated")
                navigationController?.popViewController(animated: true)
            } catch {
                showError(error, title: "Couldn't save")
            }
        }
    }
}

/// Default payment method (stored on device; the server never stores card data).
final class PaymentPreferencesViewController: UITableViewController {
    private let env: AppEnvironment
    private var methods: [PaymentMethodOption] = []

    init(env: AppEnvironment) {
        self.env = env
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Payment preferences"
        tableView.backgroundColor = DK.Color.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        Task {
            methods = (try? await env.payments.methods()) ?? []
            tableView.reloadData()
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { methods.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Your preferred method is pre-selected at checkout. QuickBite never stores card numbers — online payments are handled by Razorpay."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let method = methods[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = method.title
        content.secondaryText = method.subtitle
        cell.contentConfiguration = content
        cell.accessoryType = UserDefaults.standard.string(forKey: PaymentPreferences.defaultsKey) == method.id ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        UserDefaults.standard.set(methods[indexPath.row].id, forKey: PaymentPreferences.defaultsKey)
        Haptics.selection()
        tableView.reloadData()
    }
}

/// Order updates / promotions toggles (stored on the server) + system permission state.
final class NotificationSettingsViewController: UITableViewController {
    private let env: AppEnvironment
    private var prefs = NotificationPreferences(notifyOrderUpdates: true, notifyPromotions: false)
    private var systemStatus = "Checking…"

    init(env: AppEnvironment) {
        self.env = env
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Notifications"
        tableView.backgroundColor = DK.Color.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        Task {
            if let loaded = try? await env.notifications.preferences() { prefs = loaded }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            systemStatus = settings.authorizationStatus == .authorized ? "Allowed" : settings.authorizationStatus == .denied ? "Off — enable in iOS Settings" : "Not requested yet"
            tableView.reloadData()
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 2 : 1 }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "When push isn't available, updates still appear inside the app and in your notification inbox." : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let isOrders = indexPath.row == 0
            content.text = isOrders ? "Order updates" : "Offers & promotions"
            content.secondaryText = isOrders ? "Confirmed, on the way, delivered" : "Occasional deals from cafés near you"
            let toggle = UISwitch()
            toggle.isOn = isOrders ? prefs.notifyOrderUpdates : prefs.notifyPromotions
            toggle.onTintColor = DK.Color.primary
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                guard let self, let toggle else { return }
                if isOrders { self.prefs.notifyOrderUpdates = toggle.isOn } else { self.prefs.notifyPromotions = toggle.isOn }
                self.save()
            }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        } else {
            content.text = "iPhone notification permission"
            content.secondaryText = systemStatus
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        env.push.requestPermissionIfNeeded()
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    private func save() {
        Task {
            do {
                prefs = try await env.notifications.updatePreferences(prefs)
            } catch {
                showError(error, title: "Couldn't save preferences")
            }
        }
    }
}

/// In-app notification inbox (the push fallback).
final class NotificationsInboxViewController: UITableViewController {
    var onOpenOrder: ((String) -> Void)?
    private let env: AppEnvironment
    private var items: [AppNotification] = []

    init(env: AppEnvironment) {
        self.env = env
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Notifications"
        tableView.backgroundColor = DK.Color.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        refreshControl = UIRefreshControl()
        refreshControl?.addAction(UIAction { [weak self] _ in self?.load() }, for: .valueChanged)
        load()
    }

    private func load() {
        Task {
            do {
                items = try await env.notifications.list(page: 1).notifications
                tableView.backgroundView = items.isEmpty ? StateView(.empty(symbol: "bell.slash", title: "No notifications", message: "Order updates will show up here.")) : nil
                tableView.reloadData()
                await env.notifications.markAllRead()
            } catch {
                showError(error)
            }
            refreshControl?.endRefreshing()
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = item.title
        content.secondaryText = "\(item.body)\n\(item.createdAt.relativeDescription)"
        content.secondaryTextProperties.numberOfLines = 3
        content.textProperties.font = item.isRead ? DK.Font.body : DK.Font.bodyBold
        content.image = UIImage(systemName: item.isRead ? "bell" : "bell.badge.fill")
        content.imageProperties.tintColor = DK.Color.primary
        cell.contentConfiguration = content
        cell.accessoryType = item.orderId == nil ? .none : .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let orderId = items[indexPath.row].orderId { onOpenOrder?(orderId) }
    }
}

/// Lets you point the app at a local or deployed backend without rebuilding,
/// and shows which integrations the server has enabled.
final class ServerSettingsViewController: UITableViewController {
    private let env: AppEnvironment
    private var health: HealthResponse?
    private var healthError: String?

    init(env: AppEnvironment) {
        self.env = env
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Server & diagnostics"
        tableView.backgroundColor = DK.Color.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        check()
    }

    private func check() {
        Task {
            do {
                health = try await env.health.check()
                healthError = nil
            } catch {
                health = nil
                healthError = (error as? APIError)?.userMessage ?? error.localizedDescription
            }
            tableView.reloadData()
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 2
        case 1: return health == nil ? 1 : 6
        default: return 2
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["API server", "Server status", "Local data"][section]
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "Changing the server takes effect after restarting the app." : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.valueCell()
        cell.accessoryType = .none
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            content.text = "URL"
            content.secondaryText = env.config.apiBaseURL.absoluteString
        case (0, _):
            content.text = "Change server URL…"
            content.textProperties.color = DK.Color.primary
        case (1, 0):
            content.text = "Health"
            content.secondaryText = health.map { "\($0.status) · db \($0.database) · \($0.version)" } ?? healthError ?? "Checking…"
        case (1, let row):
            guard let features = health?.features else { break }
            let rows: [(String, Bool)] = [("Razorpay", features.razorpay), ("Demo payments", features.mockPayments), ("Push (FCM)", features.fcm), ("Demo order progression", features.demoOrderProgression), ("Demo social sign-in", features.socialLoginDemo)]
            content.text = rows[row - 1].0
            content.secondaryText = rows[row - 1].1 ? "On" : "Off"
        case (2, 0):
            content.text = "Clear cached menus & images"
            content.textProperties.color = DK.Color.primary
        default:
            content.text = "Replay onboarding"
            content.textProperties.color = DK.Color.primary
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch (indexPath.section, indexPath.row) {
        case (0, 1): promptURL()
        case (1, _): check()
        case (2, 0):
            env.cache.removeAll()
            ImagePipeline.shared.removeAll()
            toast("Cache cleared")
        case (2, _):
            env.hasSeenOnboarding = false
            toast("Onboarding will show on next launch")
        default: break
        }
    }

    private func promptURL() {
        let alert = UIAlertController(title: "Server URL", message: "e.g. http://192.168.1.20:4000 or https://quickbite-api-0zul.onrender.com", preferredStyle: .alert)
        alert.addTextField { [weak self] field in
            field.text = self?.env.config.apiBaseURL.absoluteString
            field.keyboardType = .URL
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Reset to default", style: .destructive) { _ in
            UserDefaults.standard.removeObject(forKey: AppConfiguration.baseURLOverrideKey)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text, let url = URL(string: text), url.scheme?.hasPrefix("http") == true else {
                self?.toast("That doesn't look like a valid URL", style: .error)
                return
            }
            UserDefaults.standard.set(url.absoluteString, forKey: AppConfiguration.baseURLOverrideKey)
            self?.toast("Saved — restart the app to use it")
        })
        present(alert, animated: true)
    }
}
