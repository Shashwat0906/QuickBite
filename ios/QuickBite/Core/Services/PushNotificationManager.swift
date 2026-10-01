import UIKit
import UserNotifications
#if canImport(FirebaseCore) && canImport(FirebaseMessaging)
import FirebaseCore
import FirebaseMessaging
#endif

/// Push notifications via Firebase Cloud Messaging.
///
/// - Firebase is configured only when `GoogleService-Info.plist` is bundled;
///   without it everything keeps working and order updates arrive through the
///   in-app channel (Socket.IO + notification inbox).
/// - Permission is requested at a meaningful moment (after the first order is
///   placed), not on first launch.
/// - Tapping a notification opens that order's tracking screen.
final class PushNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let notificationService: NotificationServicing
    private let session: SessionStore
    private(set) var fcmToken: String?
    /// Called when the user taps a notification for an order.
    var onOpenOrder: ((String) -> Void)?

    static var isFirebaseConfigured: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }

    init(notificationService: NotificationServicing, session: SessionStore) {
        self.notificationService = notificationService
        self.session = session
        super.init()
    }

    func configure(application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        #if canImport(FirebaseCore) && canImport(FirebaseMessaging)
        if Self.isFirebaseConfigured {
            FirebaseApp.configure()
            Messaging.messaging().delegate = self
        }
        #endif
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized {
                DispatchQueue.main.async { application.registerForRemoteNotifications() }
            }
        }
    }

    /// Ask for permission (only shows the system prompt the first time).
    func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                guard granted else { return }
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
    }

    func didRegister(deviceToken: Data) {
        #if canImport(FirebaseCore) && canImport(FirebaseMessaging)
        if Self.isFirebaseConfigured { Messaging.messaging().apnsToken = deviceToken }
        #endif
    }

    /// Associate the current FCM token with the signed-in user on the backend.
    func syncTokenWithBackend() {
        guard let token = fcmToken, session.isSignedIn else { return }
        Task { try? await notificationService.registerDevice(token: token) }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Foreground: still show the banner (the in-app toast covers the rest).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let orderId = info["orderId"] as? String {
            await MainActor.run { self.onOpenOrder?(orderId) }
        }
    }
}

#if canImport(FirebaseCore) && canImport(FirebaseMessaging)
extension PushNotificationManager: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        self.fcmToken = fcmToken
        syncTokenWithBackend()
    }
}
#endif
