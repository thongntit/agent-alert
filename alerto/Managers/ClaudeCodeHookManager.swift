import Foundation
import Combine

/// Manages Claude Code hook configuration in ~/.claude/settings.json
class ClaudeCodeHookManager: ObservableObject {
    static let shared = ClaudeCodeHookManager()

    private let fileManager = FileManager.default

    // MARK: - Configuration Paths

    var settingsPath: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/settings.json")
    }

    // MARK: - Hook ID Prefix

    static let hookIdPrefix = "alerto:"

    struct HookIds {
        static let stop = "alerto:stop"
        static let subagentStop = "alerto:subagent-stop"
        static let notification = "alerto:notification"
        static let sessionEnd = "alerto:session-end"
    }

    // MARK: - Detection

    /// Check if Claude Code is installed (settings file exists)
    func isClaudeCodeInstalled() -> Bool {
        return fileManager.fileExists(atPath: settingsPath.path)
    }

    /// Maps an Alerto hook ID to the Claude Code event name it's installed under.
    private static let eventNamesByHookId: [String: String] = [
        HookIds.stop: "Stop",
        HookIds.subagentStop: "SubagentStop",
        HookIds.notification: "Notification",
        HookIds.sessionEnd: "SessionEnd"
    ]

    /// Claude Code's own settings schema has no concept of a hook "id" — it only
    /// round-trips fields it recognizes (matcher/hooks/type/command/timeout). Any tool
    /// that reads and rewrites settings.json through that schema (e.g. Claude Code
    /// itself via /hooks or the settings UI) silently drops our custom "id" tag. So
    /// detection matches on the command signature instead, which survives that.
    private func commandLooksLikeAlerto(_ command: String) -> Bool {
        return command.contains("127.0.0.1") && command.contains("/notify")
    }

    private func eventHooks(_ hooks: [String: [[String: Any]]], for event: String) -> [[String: Any]] {
        return hooks[event] ?? []
    }

    private func entryMatchesAlerto(_ entry: [String: Any]) -> Bool {
        guard let nested = entry["hooks"] as? [[String: Any]] else { return false }
        return nested.contains { cmd in
            guard let command = cmd["command"] as? String else { return false }
            return commandLooksLikeAlerto(command)
        }
    }

    /// Check if a specific hook is installed, by matching its command signature
    /// rather than a custom "id" field (which external tools can strip).
    func isHookInstalled(hookId: String) -> Bool {
        guard let settings = loadSettings(),
              let hooks = settings["hooks"] as? [String: [[String: Any]]],
              let event = Self.eventNamesByHookId[hookId] else {
            return false
        }

        return eventHooks(hooks, for: event).contains(where: entryMatchesAlerto)
    }

    /// Check if any Alerto hook is installed
    func isAnyHookInstalled() -> Bool {
        guard let settings = loadSettings(),
              let hooks = settings["hooks"] as? [String: [[String: Any]]] else {
            return false
        }

        for (_, entries) in hooks {
            if entries.contains(where: entryMatchesAlerto) {
                return true
            }
        }
        return false
    }

    // MARK: - Installation

    /// Install Claude Code hooks (idempotent)
    /// - Parameter port: The port Alerto HTTP server is running on
    func installHooks(port: Int) throws {
        var settings = loadSettings() ?? [:]

        if settings["hooks"] == nil {
            settings["hooks"] = [String: [[String: Any]]]()
        }

        var hooks = settings["hooks"] as? [String: [[String: Any]]] ?? [:]

        // Install Stop hook (when main agent finishes)
        let stopHook = createStopHook(port: port)
        hooks = installHookConfig(hooks: hooks, event: "Stop", config: stopHook)

        // Install Notification hook (when Claude needs permission or idle)
        let notificationHook = createNotificationHook(port: port)
        hooks = installHookConfig(hooks: hooks, event: "Notification", config: notificationHook)

        // Install SessionEnd hook (when session ends)
        let sessionEndHook = createSessionEndHook(port: port)
        hooks = installHookConfig(hooks: hooks, event: "SessionEnd", config: sessionEndHook)

        settings["hooks"] = hooks
        try saveSettings(settings)
    }

    /// Install a single hook by name
    /// - Parameters:
    ///   - name: Hook name (stop, notification, session-end)
    ///   - port: The port Alerto HTTP server is running on
    func installHook(name: String, port: Int) throws {
        var settings = loadSettings() ?? [:]

        if settings["hooks"] == nil {
            settings["hooks"] = [String: [[String: Any]]]()
        }

        var hooks = settings["hooks"] as? [String: [[String: Any]]] ?? [:]

        let hookConfig: [String: Any]
        let eventName: String

        switch name {
        case "stop":
            hookConfig = createStopHook(port: port)
            eventName = "Stop"
        case "notification":
            hookConfig = createNotificationHook(port: port)
            eventName = "Notification"
        case "session-end":
            hookConfig = createSessionEndHook(port: port)
            eventName = "SessionEnd"
        default:
            return
        }

        hooks = installHookConfig(hooks: hooks, event: eventName, config: hookConfig)
        settings["hooks"] = hooks
        try saveSettings(settings)
    }

    /// Uninstall a single hook by name
    /// - Parameter name: Hook name (stop, notification, session-end)
    func uninstallHook(name: String) throws {
        guard var settings = loadSettings() else { return }

        var hooks = settings["hooks"] as? [String: [[String: Any]]] ?? [:]

        // Find the event name for this hook
        let eventName: String
        switch name {
        case "stop":
            eventName = "Stop"
        case "notification":
            eventName = "Notification"
        case "session-end":
            eventName = "SessionEnd"
        default:
            return
        }

        // Remove entries matching Alerto's command signature, not just tagged "id"
        if var eventHooks = hooks[eventName] {
            eventHooks = eventHooks.filter { !entryMatchesAlerto($0) }
            if eventHooks.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = eventHooks
            }
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        try saveSettings(settings)
    }

    private func installHookConfig(hooks: [String: [[String: Any]]], event: String, config: [String: Any]) -> [String: [[String: Any]]] {
        var mutableHooks = hooks

        // Remove any existing entry for this event that already looks like an Alerto
        // hook (matched by command signature, not "id" — see commandLooksLikeAlerto)
        // so re-installing is idempotent even if a prior entry lost its id tag.
        mutableHooks[event] = (mutableHooks[event] ?? []).filter { !entryMatchesAlerto($0) }

        // Add new hook
        mutableHooks[event]?.append(config)

        return mutableHooks
    }

    // MARK: - Hook Creators

    /// Stop: Runs when the main Claude Code agent has finished responding
    private func createStopHook(port: Int) -> [String: Any] {
        let cmd = "curl -s -X POST \"http://127.0.0.1:\(port)/notify\" -H \"Content-Type: application/json\" -d @- || curl -s -X POST \"http://127.0.0.1:\(port)/notify\" -H \"Content-Type: application/json\" -d '{\"source\":\"claude\",\"type\":\"complete\",\"message\":\"Task completed\"}'"
        return [
            "id": "\(Self.hookIdPrefix)stop",
            "hooks": [
                ["type": "command", "command": cmd]
            ]
        ]
    }

    /// SubagentStop: Runs when a Claude Code subagent has finished responding
    private func createSubagentStopHook(port: Int) -> [String: Any] {
        let cmd = "curl -s -X POST \"http://127.0.0.1:\(port)/notify\" -H \"Content-Type: application/json\" -d @- || curl -s -X POST \"http://127.0.0.1:\(port)/notify\" -H \"Content-Type: application/json\" -d '{\"source\":\"claude\",\"type\":\"complete\",\"message\":\"Subagent completed\"}'"
        return [
            "id": "\(Self.hookIdPrefix)subagent-stop",
            "hooks": [
                ["type": "command", "command": cmd]
            ]
        ]
    }

    /// Notification: Runs when Claude Code sends notifications (permission needed, idle)
    private func createNotificationHook(port: Int) -> [String: Any] {
        let cmd = "curl -s -X POST \"http://127.0.0.1:\(port)/notify\" -H \"Content-Type: application/json\" -d @- || curl -s -X POST \"http://127.0.0.1:\(port)/notify\" -H \"Content-Type: application/json\" -d '{\"source\":\"claude\",\"type\":\"attention\",\"message\":\"Claude needs attention\"}'"
        return [
            "id": "\(Self.hookIdPrefix)notification",
            "hooks": [
                ["type": "command", "command": cmd]
            ]
        ]
    }

    /// SessionEnd: Runs when a Claude Code session ends
    private func createSessionEndHook(port: Int) -> [String: Any] {
        let cmd = "curl -s -X POST \"http://127.0.0.1:\(port)/notify\" -H \"Content-Type: application/json\" -d @- || curl -s -X POST \"http://127.0.0.1:\(port)/notify\" -H \"Content-Type: application/json\" -d '{\"source\":\"claude\",\"type\":\"stop\",\"message\":\"Session ended\"}'"
        return [
            "id": "\(Self.hookIdPrefix)session-end",
            "hooks": [
                ["type": "command", "command": cmd]
            ]
        ]
    }

    // MARK: - Uninstallation

    /// Uninstall all Alerto hooks (by prefix)
    func uninstallHooks() throws {
        guard var settings = loadSettings() else { return }

        var hooks = settings["hooks"] as? [String: [[String: Any]]] ?? [:]

        // Remove all hooks with alerto: prefix
        let prefix = Self.hookIdPrefix

        for (event, eventHooks) in hooks {
            hooks[event] = eventHooks.filter { hook in
                guard let id = hook["id"] as? String else { return true }
                return !id.hasPrefix(prefix)
            }

            // Clean up empty arrays
            if hooks[event]?.isEmpty == true {
                hooks.removeValue(forKey: event)
            }
        }

        // Remove empty hooks object
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        try saveSettings(settings)
    }

    // MARK: - Private

    private func loadSettings() -> [String: Any]? {
        guard fileManager.fileExists(atPath: settingsPath.path) else { return nil }

        do {
            let data = try Data(contentsOf: settingsPath)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            print("Error loading Claude Code settings: \(error)")
            return nil
        }
    }

    private func saveSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])

        // Ensure .claude directory exists
        let claudeDir = settingsPath.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: claudeDir.path) {
            try fileManager.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        }

        try data.write(to: settingsPath)
    }
}
