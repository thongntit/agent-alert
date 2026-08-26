import Foundation
import Combine

/// Manages Codex lifecycle hooks in ~/.codex/hooks.json.
final class CodexHookManager: ObservableObject {
    static let shared = CodexHookManager()

    enum HookName: String, CaseIterable {
        case stop = "stop"
        case permissionRequest = "permission-request"
        case subagentStop = "subagent-stop"

        var eventName: String {
            switch self {
            case .stop: return "Stop"
            case .permissionRequest: return "PermissionRequest"
            case .subagentStop: return "SubagentStop"
            }
        }

        var marker: String {
            "alerto:codex-\(rawValue)"
        }

        var notificationType: String {
            switch self {
            case .permissionRequest: return "permission"
            case .stop, .subagentStop: return "complete"
            }
        }
    }

    enum ConfigurationError: LocalizedError {
        case invalidRoot
        case invalidHooks
        case invalidEvent(String)
        case invalidMatcherGroup(String)
        case invalidHandlers(String)
        case invalidHandler(String)
        case unknownHook(String)

        var errorDescription: String? {
            switch self {
            case .invalidRoot:
                return "Codex hooks.json must contain a JSON object."
            case .invalidHooks:
                return "Codex hooks.json contains an invalid hooks object."
            case .invalidEvent(let event):
                return "Codex hook event \(event) must contain an array of matcher groups."
            case .invalidMatcherGroup(let event):
                return "Codex hook event \(event) contains an invalid matcher group."
            case .invalidHandlers(let event):
                return "Codex hook event \(event) contains an invalid handlers array."
            case .invalidHandler(let event):
                return "Codex hook event \(event) contains an invalid handler."
            case .unknownHook(let name):
                return "Unknown Codex hook: \(name)."
            }
        }
    }

    private let fileManager: FileManager
    private let codexHomeURL: URL

    var hooksPath: URL {
        codexHomeURL.appendingPathComponent("hooks.json")
    }

    init(
        codexHomeURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
        fileManager: FileManager = .default
    ) {
        self.codexHomeURL = codexHomeURL
        self.fileManager = fileManager
    }

    func isCodexInstalled() -> Bool {
        fileManager.fileExists(atPath: codexHomeURL.path)
    }

    func isHookInstalled(name: String) -> Bool {
        guard let hook = HookName(rawValue: name),
              let root = try? loadConfiguration(createIfMissing: false),
              let hooks = root["hooks"] as? [String: Any] else {
            return false
        }
        return containsHandler(marker: hook.marker, in: hooks)
    }

    func isAnyHookInstalled() -> Bool {
        guard let root = try? loadConfiguration(createIfMissing: false),
              let hooks = root["hooks"] as? [String: Any] else {
            return false
        }
        return HookName.allCases.contains { containsHandler(marker: $0.marker, in: hooks) }
    }

    func installedHookNames() -> Set<String> {
        Set(HookName.allCases.filter { isHookInstalled(name: $0.rawValue) }.map(\.rawValue))
    }

    func installHooks(port: Int) throws {
        var root = try loadConfiguration(createIfMissing: true)
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        for hook in HookName.allCases {
            hooks = install(hook, port: port, into: hooks)
        }
        root["hooks"] = hooks
        try saveConfiguration(root)
    }

    func installHook(name: String, port: Int) throws {
        guard let hook = HookName(rawValue: name) else {
            throw ConfigurationError.unknownHook(name)
        }
        var root = try loadConfiguration(createIfMissing: true)
        let hooks = (root["hooks"] as? [String: Any]) ?? [:]
        root["hooks"] = install(hook, port: port, into: hooks)
        try saveConfiguration(root)
    }

    func uninstallHook(name: String) throws {
        guard let hook = HookName(rawValue: name) else {
            throw ConfigurationError.unknownHook(name)
        }
        try removeHandlers(markers: [hook.marker])
    }

    func uninstallHooks() throws {
        try removeHandlers(markers: Set(HookName.allCases.map(\.marker)))
    }

    private func install(_ hook: HookName, port: Int, into hooks: [String: Any]) -> [String: Any] {
        var updated = removingHandlers(markers: [hook.marker], from: hooks)
        var eventGroups = (updated[hook.eventName] as? [Any]) ?? []
        eventGroups.append([
            "hooks": [[
                "type": "command",
                "command": command(for: hook, port: port),
                "timeout": 5
            ]]
        ])
        updated[hook.eventName] = eventGroups
        return updated
    }

    private func removeHandlers(markers: Set<String>) throws {
        guard fileManager.fileExists(atPath: hooksPath.path) else { return }
        var root = try loadConfiguration(createIfMissing: false)
        guard let hooks = root["hooks"] as? [String: Any] else { return }
        let updated = removingHandlers(markers: markers, from: hooks)
        if updated.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = updated
        }
        try saveConfiguration(root)
    }

    private func removingHandlers(markers: Set<String>, from hooks: [String: Any]) -> [String: Any] {
        var updated = hooks
        for (event, rawGroups) in hooks {
            guard let groups = rawGroups as? [Any] else { continue }
            var retainedGroups: [Any] = []

            for rawGroup in groups {
                guard var group = rawGroup as? [String: Any],
                      let handlers = group["hooks"] as? [Any] else {
                    retainedGroups.append(rawGroup)
                    continue
                }
                let retainedHandlers = handlers.filter { rawHandler in
                    guard let handler = rawHandler as? [String: Any],
                          let command = handler["command"] as? String else {
                        return true
                    }
                    return !markers.contains(where: command.contains)
                }
                if !retainedHandlers.isEmpty {
                    group["hooks"] = retainedHandlers
                    retainedGroups.append(group)
                }
            }

            if retainedGroups.isEmpty {
                updated.removeValue(forKey: event)
            } else {
                updated[event] = retainedGroups
            }
        }
        return updated
    }

    private func containsHandler(marker: String, in hooks: [String: Any]) -> Bool {
        for rawGroups in hooks.values {
            guard let groups = rawGroups as? [Any] else { continue }
            for rawGroup in groups {
                guard let group = rawGroup as? [String: Any],
                      let handlers = group["hooks"] as? [Any] else { continue }
                for rawHandler in handlers {
                    guard let handler = rawHandler as? [String: Any],
                          let command = handler["command"] as? String else { continue }
                    if command.contains(marker) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func command(for hook: HookName, port: Int) -> String {
        let url = "http://127.0.0.1:\(port)/notify?source=codex&type=\(hook.notificationType)"
        return "curl -sS --max-time 2 -X POST \"\(url)\" -H \"Content-Type: application/json\" --data-binary @- >/dev/null 2>&1 || true; printf '{}' # \(hook.marker)"
    }

    private func loadConfiguration(createIfMissing: Bool) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: hooksPath.path) else {
            return createIfMissing ? [:] : [:]
        }

        let data = try Data(contentsOf: hooksPath)
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any] else {
            throw ConfigurationError.invalidRoot
        }
        try validate(root)
        return root
    }

    private func validate(_ root: [String: Any]) throws {
        guard let rawHooks = root["hooks"] else { return }
        guard let hooks = rawHooks as? [String: Any] else {
            throw ConfigurationError.invalidHooks
        }
        for (event, rawGroups) in hooks {
            guard let groups = rawGroups as? [Any] else {
                throw ConfigurationError.invalidEvent(event)
            }
            for rawGroup in groups {
                guard let group = rawGroup as? [String: Any] else {
                    throw ConfigurationError.invalidMatcherGroup(event)
                }
                guard let rawHandlers = group["hooks"],
                      let handlers = rawHandlers as? [Any] else {
                    throw ConfigurationError.invalidHandlers(event)
                }
                guard handlers.allSatisfy({ $0 is [String: Any] }) else {
                    throw ConfigurationError.invalidHandler(event)
                }
            }
        }
    }

    private func saveConfiguration(_ root: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try fileManager.createDirectory(at: codexHomeURL, withIntermediateDirectories: true)
        try data.write(to: hooksPath, options: .atomic)
    }
}
