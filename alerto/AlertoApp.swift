import SwiftUI
import Combine
import Sparkle
import AppKit

@main
struct AlertoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var usageManager = UsageManager.shared
    @AppStorage("showMenubarUsage") private var showMenubarUsage = true

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            if let image = MenuBarStatusRenderer.image(
                iconName: notificationManager.menubarIcon,
                snapshot: usageManager.snapshot,
                showUsage: showMenubarUsage
            ) {
                Image(nsImage: image)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private enum MenuBarStatusRenderer {
    static func image(iconName: String, snapshot: UsageSnapshot?, showUsage: Bool) -> NSImage? {
        let renderer = ImageRenderer(
            content: MenuBarStatusContent(
                iconName: iconName,
                snapshot: snapshot,
                showUsage: showUsage
            )
        )
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return nil }
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(
                width: CGFloat(cgImage.width) / renderer.scale,
                height: CGFloat(cgImage.height) / renderer.scale
            )
        )
        image.isTemplate = true
        return image
    }
}

private struct MenuBarStatusContent: View {
    let iconName: String
    let snapshot: UsageSnapshot?
    let showUsage: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)

            if showUsage {
                VStack(alignment: .leading, spacing: -1) {
                    usageRow(for: .claude)
                    usageRow(for: .codex)
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .frame(width: 62, height: 20)
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .frame(height: 20)
        .foregroundStyle(.black)
        .fixedSize()
    }

    @ViewBuilder
    private func usageRow(for provider: UsageProvider) -> some View {
        HStack(spacing: 3) {
            let limits = snapshot?.usage(for: provider)?.limits ?? []
            Text(percent(for: limits, label: "Session"))
                .frame(width: 29, alignment: .trailing)
            Text(percent(for: limits, label: "Weekly"))
                .frame(width: 29, alignment: .trailing)
        }
        .frame(width: 62, alignment: .leading)
    }

    private func percent(for limits: [UsageLimit], label: String) -> String {
        guard let limit = limits.first(where: { $0.label == label }) else { return "--" }
        return "\(Int(limit.remainingPercent.rounded()))%"
    }
}

// MARK: - Updater Delegate
//
// SPUUpdaterDelegate methods are called from a non-main thread internally by Sparkle.
// All protocol methods must be marked `nonisolated` to avoid isolation crossing violations.

final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFinishInitializationSuccessfully successfully: Bool) {
        NSLog("[UpdaterDelegate] didFinishInitializationSuccessfully: %@", successfully ? "YES" : "NO")
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        NSLog("[UpdaterDelegate] didNotFindUpdate")
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate newVersion: String) {
        NSLog("[UpdaterDelegate] didFindValidUpdate: %@", newVersion)
    }

    nonisolated func updater(_ updater: SPUUpdater, failedToFetchUpdateDataWithError error: Error) {
        let nsError = error as NSError
        NSLog("[UpdaterDelegate] failedToFetchUpdateDataWithError: %@ (code: %ld)", nsError.localizedDescription, nsError.code)
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateWithVersion version: String) {
        NSLog("[UpdaterDelegate] willInstallUpdate: %@", version)
    }
}

// MARK: - Updater Manager (Singleton)

@MainActor
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    @Published private(set) var updaterController: SPUStandardUpdaterController?
    private let delegate: UpdaterDelegate

    private init() {
        self.delegate = UpdaterDelegate()
        initialize()
    }

    private func initialize() {
        NSLog("[UpdaterManager] Initializing...")

        // Log bundle info for debugging
        NSLog("[UpdaterManager] Bundle ID: %@", Bundle.main.bundleIdentifier ?? "nil")
        NSLog("[UpdaterManager] SUFeedURL: %@", (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String) ?? "nil")
        NSLog("[UpdaterManager] SUPublicEDKey: %@", (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil) ? "set" : "NOT SET")

        do {
            NSLog("[UpdaterManager] Creating SPUStandardUpdaterController...")
            let controller = try SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: delegate,
                userDriverDelegate: nil
            )
            NSLog("[UpdaterManager] SPUStandardUpdaterController created OK")

            NSLog("[UpdaterManager] Starting updater...")
            try controller.updater.start()
            NSLog("[UpdaterManager] updater.start() succeeded")

            // Apply persisted auto-check preference
            let autoCheck = UserDefaults.standard.bool(forKey: "SUEnableAutomaticChecks")
            controller.updater.automaticallyChecksForUpdates = autoCheck
            NSLog("[UpdaterManager] automaticallyChecksForUpdates = %@", autoCheck ? "YES" : "NO")

            self.updaterController = controller
        } catch {
            let nsError = error as NSError
            NSLog("[UpdaterManager] Updater FAILED: %@ (code: %ld)", nsError.localizedDescription, nsError.code)
            self.updaterController = nil
        }
    }

    /// Call this from the Settings UI toggle to enable/disable auto-update checks.
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let controller = updaterController else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
        UserDefaults.standard.set(enabled, forKey: "SUEnableAutomaticChecks")
        NSLog("[UpdaterManager] automaticallyChecksForUpdates set to %@", enabled ? "YES" : "NO")
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var updaterManager: UpdaterManager { UpdaterManager.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[AppDelegate] applicationDidFinishLaunching")
        NotificationManager.migrateLegacySettingsIfNeeded()
        URLSchemeHandler.shared.registerHandler()
        NotificationOverlayManager.shared.setup()
        SystemNotificationService.shared.registerDelegate()

        // Start the direct quota fetch at launch so the menu is populated when opened.
        Task { @MainActor in
            _ = UsageManager.shared
        }

        // Trigger initialization by accessing the singleton
        _ = updaterManager.updaterController
        NSLog("[AppDelegate] UpdaterManager shared initialized")

        Task {
            await HTTPServerManager.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await HTTPServerManager.shared.stop()
        }
    }
}
