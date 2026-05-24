import SwiftUI
import Sparkle
import ServiceManagement
import UserNotifications

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            IntegrationsSettingsView()
                .tabItem {
                    Label("Integrations", systemImage: "link")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }

            #if DEBUG
            LogViewerView()
                .tabItem {
                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                }
            #endif
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage("notificationStyle") private var notificationStyleRaw = NotificationStyle.overlay.rawValue
    @AppStorage("overlayDuration") private var overlayDuration = 3.0
    @AppStorage("playSound") private var playSound = true
    @AppStorage("selectedSound") private var selectedSound = "Glass"
    @AppStorage("showMenubarUsage") private var showMenubarUsage = true
    @AppStorage("dedupEnabled") private var dedupEnabled = true
    @AppStorage("dedupWindowSeconds") private var dedupWindowSeconds = 5.0

    @StateObject private var serverManager = HTTPServerManager.shared
    @StateObject private var launchAtLoginService = LaunchAtLoginService.shared
    @StateObject private var systemNotificationService = SystemNotificationService.shared
    @State private var portString: String = ""

    private var notificationStyle: Binding<NotificationStyle> {
        Binding(
            get: { NotificationStyle(rawValue: notificationStyleRaw) ?? .overlay },
            set: { newValue in
                notificationStyleRaw = newValue.rawValue
                if newValue == .system {
                    systemNotificationService.requestAuthorizationIfNeeded()
                }
            }
        )
    }

    let availableSounds = ["Glass", "Ping", "Pop", "Purr", "Blow", "Hero", "Submarine"]

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLoginService.isEnabled },
                    set: { enabled in
                        Task {
                            if enabled {
                                launchAtLoginService.register()
                            } else {
                                launchAtLoginService.unregister()
                            }
                        }
                    }
                ))

                if launchAtLoginService.status == .requiresApproval {
                    Button("Open System Settings") {
                        openLoginItemsSettings()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            Section("Menu Bar") {
                Toggle("Show remaining usage", isOn: $showMenubarUsage)

                Text("Shows Claude Code and Codex session and weekly percentages beside the bell.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Notifications") {
                Picker("Notification style", selection: notificationStyle) {
                    ForEach(NotificationStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)

                Text("System notifications respect Focus and Do Not Disturb.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if notificationStyle.wrappedValue == .overlay {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Overlay duration")
                            Spacer()
                            Text("\(Int(overlayDuration))s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $overlayDuration, in: 1...10, step: 1)
                    }
                }

                if notificationStyle.wrappedValue == .system,
                   systemNotificationService.authorizationStatus == .denied {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notifications are disabled for Alerto.")
                                .font(.caption)
                            Button("Open Notification Settings") {
                                openNotificationSettings()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                }
            }

            Section("Deduplication") {
                Toggle("Suppress repeat notifications", isOn: $dedupEnabled)

                if dedupEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Window")
                            Spacer()
                            Text("\(Int(dedupWindowSeconds))s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $dedupWindowSeconds, in: 1...30, step: 1)
                    }

                    Text("Identical notifications (same source, type, and message) arriving within this window are skipped.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Sound") {
                Toggle("Play sound", isOn: $playSound)

                if playSound {
                    Picker("Notification sound", selection: $selectedSound) {
                        ForEach(availableSounds, id: \.self) { sound in
                            Text(sound).tag(sound)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Spacer()
                        Button("Preview Sound") {
                            NSSound(named: NSSound.Name(selectedSound))?.play()
                        }
                    }
                }
            }

            Section("HTTP Server") {
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)

                    Text(serverManager.status.displayText)

                    Spacer()

                    Button(serverManager.status == .stopped ? "Start" : "Stop") {
                        Task {
                            if serverManager.status == .stopped {
                                await serverManager.start()
                            } else {
                                await serverManager.stop()
                            }
                        }
                    }
                }

                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", text: $portString)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: portString) { _, newValue in
                            let port = Int(newValue)
                            if let port = port, port >= 1 && port <= 65535 {
                                Task {
                                    await serverManager.updatePort(port)
                                }
                            }
                        }
                }

                Text("Allows external tools to send notifications via HTTP requests.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            portString = String(serverManager.port)
            launchAtLoginService.refreshStatus()
            systemNotificationService.refreshAuthorizationStatus()
        }
    }

    private func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?Alerto") {
            NSWorkspace.shared.open(url)
        }
    }

    private var statusColor: Color {
        switch serverManager.status {
        case .running:
            return .green
        case .stopped:
            return .gray
        case .error:
            return .red
        }
    }
}

struct IntegrationsSettingsView: View {
    @StateObject private var serverManager = HTTPServerManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Integrations")
                    .font(.title2)
                    .fontWeight(.semibold)

                ClaudeCodeIntegrationView(port: serverManager.port)

                Divider()

                CodexIntegrationView(port: serverManager.port)

                Spacer()
            }
            .padding()
        }
    }
}

struct CodexIntegrationView: View {
    let port: Int

    @StateObject private var hookManager = CodexHookManager.shared
    @State private var isInstalling = false
    @State private var installError: String?
    @State private var showActivationMessage = false
    @State private var hookStopEnabled = false
    @State private var hookPermissionRequestEnabled = false
    @State private var hookSubagentStopEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Section {
                HStack {
                    Image(systemName: "terminal.fill")
                        .font(.title2)
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Codex")
                            .font(.headline)

                        Text(hookStatusText)
                            .font(.caption)
                            .foregroundColor(hookStatusColor)
                    }

                    Spacer()

                    if isInstalling {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }

            Section("Server") {
                HStack {
                    Text("Port")
                    Spacer()
                    Text("\(port)")
                        .foregroundColor(.secondary)
                }
            }

            Section("Hooks") {
                Toggle("Stop - When main turn finishes", isOn: $hookStopEnabled)
                    .onChange(of: hookStopEnabled) { _, enabled in
                        toggleHook("stop", enabled: enabled)
                    }

                Toggle("PermissionRequest - When approval is needed", isOn: $hookPermissionRequestEnabled)
                    .onChange(of: hookPermissionRequestEnabled) { _, enabled in
                        toggleHook("permission-request", enabled: enabled)
                    }

                Toggle("SubagentStop - When a subagent finishes", isOn: $hookSubagentStopEnabled)
                    .onChange(of: hookSubagentStopEnabled) { _, enabled in
                        toggleHook("subagent-stop", enabled: enabled)
                    }
            }
            .onAppear {
                refreshHookStates()
            }

            Section {
                HStack {
                    Button("Install All") {
                        installAllHooks()
                    }
                    .disabled(isInstalling || allHooksEnabled)

                    Button("Remove All") {
                        removeAllHooks()
                    }
                    .disabled(isInstalling || !anyHookEnabled)
                    .foregroundColor(.red)
                }

                if let installError {
                    Text(installError)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if showActivationMessage {
                    Text("Start a new Codex session, run /hooks, and trust the installed hooks.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Section {
                Text("Alerto manages user-level hooks in ~/.codex/hooks.json. Codex requires new or changed hooks to be reviewed and trusted.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var hookStatusText: String {
        if !hookManager.isCodexInstalled() {
            return "Codex not detected"
        }
        if hookManager.isAnyHookInstalled() {
            let count = [hookStopEnabled, hookPermissionRequestEnabled, hookSubagentStopEnabled].filter { $0 }.count
            return "\(count) hook(s) installed"
        }
        return "No hooks installed"
    }

    private var hookStatusColor: Color {
        if !hookManager.isCodexInstalled() {
            return .orange
        }
        return hookManager.isAnyHookInstalled() ? .green : .secondary
    }

    private var allHooksEnabled: Bool {
        hookStopEnabled && hookPermissionRequestEnabled && hookSubagentStopEnabled
    }

    private var anyHookEnabled: Bool {
        hookStopEnabled || hookPermissionRequestEnabled || hookSubagentStopEnabled
    }

    private func refreshHookStates() {
        hookStopEnabled = hookManager.isHookInstalled(name: "stop")
        hookPermissionRequestEnabled = hookManager.isHookInstalled(name: "permission-request")
        hookSubagentStopEnabled = hookManager.isHookInstalled(name: "subagent-stop")
    }

    private func toggleHook(_ name: String, enabled: Bool) {
        isInstalling = true
        installError = nil
        showActivationMessage = false

        do {
            if enabled {
                try hookManager.installHook(name: name, port: port)
                showActivationMessage = true
            } else {
                try hookManager.uninstallHook(name: name)
            }
        } catch {
            installError = "Failed to \(enabled ? "install" : "remove"): \(error.localizedDescription)"
            refreshHookStates()
        }

        isInstalling = false
    }

    private func installAllHooks() {
        isInstalling = true
        installError = nil

        do {
            try hookManager.installHooks(port: port)
            refreshHookStates()
            showActivationMessage = true
        } catch {
            installError = "Failed to install: \(error.localizedDescription)"
        }

        isInstalling = false
    }

    private func removeAllHooks() {
        isInstalling = true
        installError = nil
        showActivationMessage = false

        do {
            try hookManager.uninstallHooks()
            refreshHookStates()
        } catch {
            installError = "Failed to remove: \(error.localizedDescription)"
        }

        isInstalling = false
    }
}

struct ClaudeCodeIntegrationView: View {
    let port: Int

    @StateObject private var hookManager = ClaudeCodeHookManager.shared
    @State private var isInstalling = false
    @State private var installError: String?
    @State private var showSuccessMessage = false

    // Individual hook states
    @State private var hookStopEnabled = false
    @State private var hookNotificationEnabled = false
    @State private var hookSessionEndEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status Section
            Section {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Code")
                            .font(.headline)

                        Text(hookStatusText)
                            .font(.caption)
                            .foregroundColor(hookStatusColor)
                    }

                    Spacer()

                    if isInstalling {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }

            Divider()

            // Port Configuration
            Section("Server") {
                HStack {
                    Text("Port")
                    Spacer()
                    Text("\(port)")
                        .foregroundColor(.secondary)
                }
            }

            // Hook Events Section
            Section("Hooks") {
                Toggle("Stop - When main agent finishes", isOn: $hookStopEnabled)
                    .onChange(of: hookStopEnabled) { _, newValue in
                        toggleHook("stop", enabled: newValue)
                    }

                Toggle("Notification - When Claude needs attention", isOn: $hookNotificationEnabled)
                    .onChange(of: hookNotificationEnabled) { _, newValue in
                        toggleHook("notification", enabled: newValue)
                    }

                Toggle("SessionEnd - When session ends", isOn: $hookSessionEndEnabled)
                    .onChange(of: hookSessionEndEnabled) { _, newValue in
                        toggleHook("session-end", enabled: newValue)
                    }
            }
            .onAppear {
                refreshHookStates()
            }

            // Actions Section
            Section {
                HStack {
                    Button("Install All") {
                        installAllHooks()
                    }
                    .disabled(isInstalling || allHooksEnabled)

                    Button("Remove All") {
                        removeAllHooks()
                    }
                    .disabled(isInstalling || !anyHookEnabled)
                    .foregroundColor(.red)
                }

                if let error = installError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if showSuccessMessage {
                    Text("Hooks updated successfully!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            // Info Section
            Section {
                Text("Check individual hooks to enable/disable them. Use Install All/Remove All for bulk operations.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var hookStatusText: String {
        if !hookManager.isClaudeCodeInstalled() {
            return "Claude Code not detected"
        }
        if hookManager.isAnyHookInstalled() {
            let count = [hookStopEnabled, hookNotificationEnabled, hookSessionEndEnabled].filter { $0 }.count
            return "\(count) hook(s) enabled"
        }
        return "No hooks installed"
    }

    private var hookStatusColor: Color {
        if !hookManager.isClaudeCodeInstalled() {
            return .orange
        }
        if hookManager.isAnyHookInstalled() {
            return .green
        }
        return .secondary
    }

    private var allHooksEnabled: Bool {
        hookStopEnabled && hookNotificationEnabled && hookSessionEndEnabled
    }

    private var anyHookEnabled: Bool {
        hookStopEnabled || hookNotificationEnabled || hookSessionEndEnabled
    }

    private func refreshHookStates() {
        hookStopEnabled = hookManager.isHookInstalled(hookId: "alerto:stop")
        hookNotificationEnabled = hookManager.isHookInstalled(hookId: "alerto:notification")
        hookSessionEndEnabled = hookManager.isHookInstalled(hookId: "alerto:session-end")
    }

    private func toggleHook(_ hookName: String, enabled: Bool) {
        isInstalling = true
        installError = nil
        showSuccessMessage = false

        do {
            if enabled {
                try hookManager.installHook(name: hookName, port: port)
            } else {
                try hookManager.uninstallHook(name: hookName)
            }
            showSuccessMessage = true
        } catch {
            installError = "Failed to \(enabled ? "install" : "remove"): \(error.localizedDescription)"
            // Revert state on error
            refreshHookStates()
        }

        isInstalling = false
    }

    private func installAllHooks() {
        isInstalling = true
        installError = nil
        showSuccessMessage = false

        do {
            try hookManager.installHooks(port: port)
            refreshHookStates()
            showSuccessMessage = true
        } catch {
            installError = "Failed to install: \(error.localizedDescription)"
        }

        isInstalling = false
    }

    private func removeAllHooks() {
        isInstalling = true
        installError = nil
        showSuccessMessage = false

        do {
            try hookManager.uninstallHooks()
            refreshHookStates()
            showSuccessMessage = true
        } catch {
            installError = "Failed to remove: \(error.localizedDescription)"
        }

        isInstalling = false
    }
}

struct OpenCodeIntegrationView: View {
    let port: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OpenCode integration is no longer supported.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct CodeBlockView: View {
    let code: String
    @State private var codeText: String = ""
    
    var body: some View {
        TextEditor(text: $codeText)
            .font(.system(.caption, design: .monospaced))
            .padding(4)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .frame(height: 150)
            .onAppear {
                codeText = code
            }
    }
}

struct AboutView: View {
    @ObservedObject private var notificationManager = NotificationManager.shared

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var updaterController: SPUStandardUpdaterController? {
        UpdaterManager.shared.updaterController
    }

    private var isAutoCheckEnabled: Bool {
        updaterController?.updater.automaticallyChecksForUpdates ?? false
    }

    var body: some View {
        VStack(spacing: 20) {
            Image("AppIcon")
                .resizable()
                .frame(width: 64, height: 64)
                .cornerRadius(12)

            Text("Alerto")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("A macOS notification app for Claude Code")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding()

            Divider()

            VStack(spacing: 12) {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { isAutoCheckEnabled },
                    set: { enabled in
                        Task { @MainActor in
                            UpdaterManager.shared.setAutomaticallyChecksForUpdates(enabled)
                        }
                    }
                ))
                .toggleStyle(.switch)

                Button("Check for Updates") {
                    if let uc = updaterController {
                        uc.checkForUpdates(nil)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(updaterController?.updater.canCheckForUpdates == false)
            }
            .padding(.horizontal)

        }
        .padding()
    }
}
