import UIKit

/// A coordinator owns a navigation flow: it creates view controllers, injects
/// their dependencies and decides what comes next. View controllers never push
/// or present each other directly — they report intent to a coordinator.
@MainActor
protocol Coordinator: AnyObject {
    var children: [Coordinator] { get set }
    func start()
}

extension Coordinator {
    func addChild(_ child: Coordinator) { children.append(child) }
    func removeChild(_ child: Coordinator) { children.removeAll { $0 === child } }
}

/// Every navigation intent a screen can express. Implemented by `MainCoordinator`.
@MainActor
protocol AppRouting: AnyObject {
    func showCafe(id: String)
    func showCafeList(title: String, category: String?)
    func showSearch(query: String?)
    func showCart()
    func showOrder(id: String)
    func showOrdersTab()
    func showWriteReview(orderId: String, cafeName: String, onDone: (() -> Void)?)
    func showCafeReviews(cafe: Cafe)
    func showLocationPicker()
    func showEditProfile()
    func showAddresses()
    func showPaymentPreferences()
    func showNotificationSettings()
    func showNotificationsInbox()
    func showMyReviews()
    func showServerSettings()
    /// Runs `action` immediately when signed in, otherwise after a successful sign-in.
    func requireSignIn(reason: String, then action: @escaping () -> Void)
    func signOut()
}
