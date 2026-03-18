import Foundation
import UIKit
import UserNotifications

@MainActor
protocol NotificationPushSyncing {
    var isAuthenticated: Bool { get }
    func sendTestPush(title: String, body: String) async throws
    func upsertPushToken(
        token: String,
        environment: MobilePushEnvironment,
        platform: String,
        bundleId: String,
        deviceId: String?
    ) async throws
    func removePushToken(token: String) async throws
}

@MainActor
struct LiveNotificationPushSyncer: NotificationPushSyncing {
    private let authManager: AuthManager
    private let routeClient: MobilePushRouteClient

    init(
        authManager: AuthManager? = nil,
        routeClient: MobilePushRouteClient? = nil
    ) {
        let resolvedAuthManager = authManager ?? AuthManager.shared
        self.authManager = resolvedAuthManager
        self.routeClient = routeClient ?? MobilePushRouteClient(authManager: resolvedAuthManager)
    }

    var isAuthenticated: Bool {
        authManager.isAuthenticated
    }

    func sendTestPush(title: String, body: String) async throws {
        _ = try await routeClient.sendTestPush(title: title, body: body)
    }

    func upsertPushToken(
        token: String,
        environment: MobilePushEnvironment,
        platform: String,
        bundleId: String,
        deviceId: String?
    ) async throws {
        try await routeClient.upsertPushToken(
            token: token,
            environment: environment,
            platform: platform,
            bundleId: bundleId,
            deviceId: deviceId
        )
    }

    func removePushToken(token: String) async throws {
        try await routeClient.removePushToken(token: token)
    }
}

@MainActor
protocol NotificationSystemHandling {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    var isRegisteredForRemoteNotifications: Bool { get }
    func registerForRemoteNotifications()
    func openSettings()
}

@MainActor
struct LiveNotificationSystem: NotificationSystemHandling {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }

    var isRegisteredForRemoteNotifications: Bool {
        UIApplication.shared.isRegisteredForRemoteNotifications
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

@MainActor
protocol NotificationDeviceInfoProviding {
    var bundleIdentifier: String? { get }
    var vendorIdentifier: String? { get }
}

@MainActor
struct LiveNotificationDeviceInfo: NotificationDeviceInfoProviding {
    var bundleIdentifier: String? {
        Bundle.main.bundleIdentifier
    }

    var vendorIdentifier: String? {
        UIDevice.current.identifierForVendor?.uuidString
    }
}

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isRegisteredForRemoteNotifications = false

    private let pushSyncer: NotificationPushSyncing
    private let tokenStore: NotificationTokenStoring
    private let routeStore: NotificationRouteStore
    private let system: NotificationSystemHandling
    private let deviceInfo: NotificationDeviceInfoProviding
    private var isRequestInFlight = false

    private override init() {
        self.pushSyncer = LiveNotificationPushSyncer()
        self.tokenStore = NotificationTokenStore.shared
        self.routeStore = .shared
        self.system = LiveNotificationSystem()
        self.deviceInfo = LiveNotificationDeviceInfo()
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    init(
        pushSyncer: NotificationPushSyncing,
        tokenStore: NotificationTokenStoring,
        routeStore: NotificationRouteStore,
        system: NotificationSystemHandling,
        deviceInfo: NotificationDeviceInfoProviding,
        observeDidBecomeActive: Bool
    ) {
        self.pushSyncer = pushSyncer
        self.tokenStore = tokenStore
        self.routeStore = routeStore
        self.system = system
        self.deviceInfo = deviceInfo
        super.init()
        if observeDidBecomeActive {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleDidBecomeActive),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
        }
    }

    var statusLabel: String {
        switch authorizationStatus {
        case .authorized:
            return "Enabled"
        case .denied:
            return "Disabled"
        case .notDetermined:
            return "Not Determined"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    @objc private func handleDidBecomeActive() {
        Task {
            await refreshAuthorizationStatus()
        }
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await system.authorizationStatus()
        isRegisteredForRemoteNotifications = system.isRegisteredForRemoteNotifications

        if isAuthorized {
            registerForRemoteNotifications()
        } else {
            await removeTokenIfNeeded()
        }
    }

    func requestAuthorizationIfNeeded(trigger: NotificationRequestTrigger) async {
        if isRequestInFlight {
            return
        }

        await refreshAuthorizationStatus()

        guard authorizationStatus == .notDetermined else {
            if isAuthorized {
                registerForRemoteNotifications()
            }
            return
        }

        isRequestInFlight = true
        defer { isRequestInFlight = false }

        do {
            let granted = try await system.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            if granted {
                registerForRemoteNotifications()
            }
        } catch {
            print("🔔 Notification permission request failed (\(trigger.rawValue)): \(error)")
        }
    }

    func openSystemSettings() {
        system.openSettings()
    }

    func sendTestNotification() async throws {
        await requestAuthorizationIfNeeded(trigger: .settings)
        await refreshAuthorizationStatus()

        guard isAuthorized else {
            throw NotificationTestError.notAuthorized
        }

        await syncTokenIfPossible()

        guard tokenStore.load() != nil else {
            throw NotificationTestError.deviceTokenMissing
        }

        guard pushSyncer.isAuthenticated else {
            throw NotificationTestError.notAuthenticated
        }

        try await pushSyncer.sendTestPush(
            title: "cmux test",
            body: "Push notification from cmux"
        )
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        tokenStore.save(token)
        Task {
            await syncTokenIfPossible()
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        print("🔔 Failed to register for remote notifications: \(error)")
    }

    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        routeStore.store(userInfo: userInfo)
    }

    var pendingRouteForTesting: NotificationRoute? {
        routeStore.pendingRoute
    }

    func syncTokenIfPossible() async {
        await refreshAuthorizationStatus()
        guard isAuthorized else {
            await removeTokenIfNeeded()
            return
        }

        guard pushSyncer.isAuthenticated else {
            return
        }

        guard let token = tokenStore.load() else {
            return
        }

        guard let bundleId = deviceInfo.bundleIdentifier else {
            print("🔔 Missing bundle identifier, cannot register push token.")
            return
        }

        let environment: MobilePushEnvironment = Environment.current == .development
            ? .development
            : .production
        let deviceId = deviceInfo.vendorIdentifier

        do {
            try await pushSyncer.upsertPushToken(
                token: token,
                environment: environment,
                platform: "ios",
                bundleId: bundleId,
                deviceId: deviceId
            )
        } catch {
            print("🔔 Failed to sync push token: \(error)")
        }
    }

    func unregisterFromServer() async {
        guard let token = tokenStore.load() else {
            return
        }

        guard pushSyncer.isAuthenticated else {
            tokenStore.clear()
            return
        }

        do {
            try await pushSyncer.removePushToken(token: token)
            tokenStore.clear()
        } catch {
            print("🔔 Failed to remove push token: \(error)")
        }
    }

    private func removeTokenIfNeeded() async {
        guard tokenStore.load() != nil else {
            return
        }
        await unregisterFromServer()
    }

    private func registerForRemoteNotifications() {
        if system.isRegisteredForRemoteNotifications {
            isRegisteredForRemoteNotifications = true
            return
        }
        system.registerForRemoteNotifications()
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .list, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            handleNotificationUserInfo(response.notification.request.content.userInfo)
        }
    }
}

enum NotificationRequestTrigger: String {
    case createConversation
    case sendMessage
    case settings
}

enum NotificationTestError: Error, LocalizedError {
    case notAuthorized
    case notAuthenticated
    case deviceTokenMissing

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Notifications aren’t enabled for this device."
        case .notAuthenticated:
            return "You need to be signed in to send a test notification."
        case .deviceTokenMissing:
            return "No device token yet. Reopen the app after granting permission."
        }
    }
}
