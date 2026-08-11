import Foundation
import UIKit
import UserNotifications

/// APNs registration and routing of order pushes back into the UI.
///
/// The payloads the backend sends look like:
/// ```json
/// { "aps": { "alert": { ... }, "sound": "default" },
///   "type": "order.acknowledged", "order_id": "<uuid>" }
/// ```
@MainActor
final class PushService: NSObject, ObservableObject {

    static let shared = PushService()

    /// Posted when a push arrives that should make the order lists refresh.
    static let didReceiveOrderUpdate = Notification.Name("TensoraDidReceiveOrderUpdate")
    /// Posted when the user taps a push for a specific order.
    static let didOpenOrder = Notification.Name("TensoraDidOpenOrder")

    @Published private(set) var isAuthorized = false
    @Published private(set) var deviceToken: String?

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorizationState() }
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            isAuthorized = false
        }
    }

    func refreshAuthorizationState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        if isAuthorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func handleRegistration(tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        Task {
            try? await AppEnvironment.shared.backend.registerPushToken(token)
        }
    }

    private func route(userInfo: [AnyHashable: Any], opened: Bool) {
        let orderID = (userInfo["order_id"] as? String).flatMap(UUID.init(uuidString:))
        var payload: [AnyHashable: Any] = [:]
        if let orderID { payload["orderID"] = orderID }

        NotificationCenter.default.post(
            name: opened ? PushService.didOpenOrder : PushService.didReceiveOrderUpdate,
            object: nil,
            userInfo: payload
        )
    }
}

extension PushService: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        Task { @MainActor in
            self.route(userInfo: userInfo, opened: false)
        }
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            self.route(userInfo: userInfo, opened: true)
        }
        completionHandler()
    }
}
