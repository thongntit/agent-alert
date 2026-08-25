import Foundation
import Combine
import SwiftUI
import AppKit

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private static let maxNotificationHistory = 100

    @Published var notifications: [AgenticNotification] = []
    @Published var showOverlay = false
    @Published var currentNotification: AgenticNotification?

    @AppStorage("playSound") private var playSound = true
    @AppStorage("selectedSound") private var selectedSound = "Glass"
    @AppStorage("notificationStyle") private var notificationStyleRaw = NotificationStyle.overlay.rawValue
    @AppStorage("overlayDuration") private var overlayDuration = 3.0
    @AppStorage("dedupEnabled") private var dedupEnabled = true
    @AppStorage("dedupWindowSeconds") private var dedupWindowSeconds = 5.0
    @AppStorage("silenceHoursEnabled") private var silenceHoursEnabled = false
    @AppStorage("silenceHoursStartMinute") private var silenceHoursStartMinute = SilenceHoursSchedule.defaultStartMinute
    @AppStorage("silenceHoursEndMinute") private var silenceHoursEndMinute = SilenceHoursSchedule.defaultEndMinute

    private var overlayTimer: Timer?
    private var deduplicator = NotificationDeduplicator()

    private var notificationStyle: NotificationStyle {
        NotificationStyle(rawValue: notificationStyleRaw) ?? .overlay
    }

    private var silenceHoursSchedule: SilenceHoursSchedule {
        SilenceHoursSchedule(
            isEnabled: silenceHoursEnabled,
            startMinute: silenceHoursStartMinute,
            endMinute: silenceHoursEndMinute
        )
    }

    private init() {}

    /// One-time migration from the legacy `showOverlay` boolean to `notificationStyle`.
    /// Called from AppDelegate on launch.
    static func migrateLegacySettingsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "notificationStyle") == nil else { return }

        let legacy = defaults.object(forKey: "showOverlay") as? Bool
        let migratedStyle: NotificationStyle = (legacy == false) ? .off : .overlay
        defaults.set(migratedStyle.rawValue, forKey: "notificationStyle")

        Task { @MainActor in
            AppLogger.shared.info(
                "Migrated showOverlay=\(legacy.map(String.init(describing:)) ?? "nil") → notificationStyle=\(migratedStyle.rawValue)",
                category: .system
            )
        }
    }

    func handleNotification(source: NotificationSource, type: NotificationType, message: String, hookType: HookType? = nil, rawMessage: String? = nil) {
        let notification = AgenticNotification(source: source, type: type, message: message, hookType: hookType, rawMessage: rawMessage)
        AppLogger.shared.info("Received: source=\(source.rawValue), type=\(type.rawValue), message=\(String(message.prefix(256)))", category: .notification)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.showNotification(notification)
        }
    }

    private func showNotification(_ notification: AgenticNotification) {
        if isDuplicate(of: notification) {
            AppLogger.shared.info("Suppressed duplicate within \(Int(dedupWindowSeconds))s window", category: .notification)
            return
        }

        if silenceHoursSchedule.isActive() {
            AppLogger.shared.info("Silence hours active; notification saved to history", category: .display)
            appendToHistory(notification)
            return
        }

        switch notificationStyle {
        case .overlay:
            currentNotification = notification
            playInAppSoundIfEnabled()
            AppLogger.shared.info("Overlay shown", category: .display)
            showOverlay = true
            overlayTimer?.invalidate()
            overlayTimer = Timer.scheduledTimer(withTimeInterval: overlayDuration, repeats: false) { [weak self] _ in
                self?.dismissOverlay()
            }
            NotificationOverlayManager.shared.show(notification: notification, duration: overlayDuration)

        case .system:
            AppLogger.shared.info("System notification posted", category: .display)
            SystemNotificationService.shared.post(
                notification,
                playSound: playSound,
                soundName: selectedSound
            )
            appendToHistory(notification)

        case .off:
            AppLogger.shared.info("Notification style off; history-only", category: .display)
            appendToHistory(notification)
        }
    }

    private func fingerprint(for notification: AgenticNotification) -> String {
        "\(notification.source.rawValue)|\(notification.type.rawValue)|\(notification.message)"
    }

    private func isDuplicate(of notification: AgenticNotification) -> Bool {
        guard dedupEnabled, dedupWindowSeconds > 0 else { return false }
        return deduplicator.isDuplicate(
            fingerprint: fingerprint(for: notification),
            within: dedupWindowSeconds
        )
    }

    private func playInAppSoundIfEnabled() {
        if playSound {
            NSSound(named: NSSound.Name(selectedSound))?.play()
            AppLogger.shared.info("Sound played: \(selectedSound)", category: .display)
        } else {
            AppLogger.shared.debug("Sound skipped (setting disabled)", category: .display)
        }
    }

    private func appendToHistory(_ notification: AgenticNotification) {
        notifications.insert(notification, at: 0)
        if notifications.count > Self.maxNotificationHistory {
            notifications = Array(notifications.prefix(Self.maxNotificationHistory))
        }
        AppLogger.shared.info("Notification added to history", category: .notification)
    }

    func dismissOverlay() {
        showOverlay = false
        if let notification = currentNotification {
            appendToHistory(notification)
        }
        currentNotification = nil
    }

    func clearAll() {
        notifications.removeAll()
    }

    func markAsRead(_ notification: AgenticNotification) {
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].isRead = true
        }
    }

    var menubarIcon: String {
        let hasUnread = !notifications.filter { !$0.isRead }.isEmpty || currentNotification != nil
        return hasUnread ? "bell.badge.fill" : "bell.fill"
    }

    func markAllAsRead() {
        for i in 0..<notifications.count {
            notifications[i].isRead = true
        }
    }
}
