import Combine
import Foundation

@MainActor
final class CodingAgentIntegrationStore: ObservableObject {
    static let shared = CodingAgentIntegrationStore()

    @Published private(set) var snapshots: [CodingAgent: AgentIntegrationSnapshot] = [:]

    private let fileManager: FileManager
    private let homeDirectoryURL: URL
    private let environment: [String: String]
    private let userDefaults: UserDefaults
    private var errors: [CodingAgent: String] = [:]

    init(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
        self.environment = environment
        self.userDefaults = userDefaults
    }

    func refresh(port: Int) {
        snapshots = Dictionary(uniqueKeysWithValues: CodingAgent.allCases.map { agent in
            (agent, makeSnapshot(for: agent, port: port))
        })
    }

    func snapshot(for agent: CodingAgent, port: Int) -> AgentIntegrationSnapshot {
        snapshots[agent] ?? makeSnapshot(for: agent, port: port)
    }

    func setEnabled(_ enabled: Bool, for agent: CodingAgent, port: Int) {
        perform(for: agent, port: port) {
            if enabled {
                try install(agent: agent, events: agent.defaultEvents, port: port)
            } else {
                try uninstall(agent: agent)
            }
        }
    }

    func setEvent(_ event: IntegrationEvent, enabled: Bool, for agent: CodingAgent, port: Int) {
        guard agent.supportedEvents.contains(event) else { return }
        var events = snapshot(for: agent, port: port).enabledEvents
        if enabled {
            events.insert(event)
        } else {
            events.remove(event)
        }

        perform(for: agent, port: port) {
            if events.isEmpty {
                try uninstall(agent: agent)
            } else {
                try install(agent: agent, events: events, port: port)
            }
        }
    }

    func update(_ agent: CodingAgent, port: Int) {
        let currentEvents = snapshot(for: agent, port: port).enabledEvents
        perform(for: agent, port: port) {
            try install(
                agent: agent,
                events: currentEvents.isEmpty ? agent.defaultEvents : currentEvents,
                port: port
            )
        }
    }

    func updateInstalledIntegrations(port: Int) {
        let installed = CodingAgent.allCases.compactMap { agent -> (CodingAgent, Set<IntegrationEvent>)? in
            let current = snapshot(for: agent, port: port)
            guard current.isEnabled else { return nil }
            return (agent, current.enabledEvents)
        }

        for (agent, events) in installed {
            do {
                try install(agent: agent, events: events, port: port)
                errors.removeValue(forKey: agent)
            } catch {
                errors[agent] = error.localizedDescription
            }
        }
        refresh(port: port)
    }

    func setPathOverride(_ url: URL, for agent: CodingAgent, port: Int) {
        guard !snapshot(for: agent, port: port).isEnabled else { return }
        userDefaults.set(url.standardizedFileURL.path, forKey: pathOverrideKey(for: agent))
        errors.removeValue(forKey: agent)
        refresh(port: port)
    }

    func resetPathOverride(for agent: CodingAgent, port: Int) {
        guard !snapshot(for: agent, port: port).isEnabled else { return }
        userDefaults.removeObject(forKey: pathOverrideKey(for: agent))
        errors.removeValue(forKey: agent)
        refresh(port: port)
    }

    func hasPathOverride(for agent: CodingAgent) -> Bool {
        userDefaults.string(forKey: pathOverrideKey(for: agent)) != nil
    }

    private func perform(for agent: CodingAgent, port: Int, operation: () throws -> Void) {
        do {
            try operation()
            errors.removeValue(forKey: agent)
        } catch {
            errors[agent] = error.localizedDescription
        }
        refresh(port: port)
    }

    private func makeSnapshot(for agent: CodingAgent, port: Int) -> AgentIntegrationSnapshot {
        let root = resolvedDirectory(for: agent)
        let detected = isDetected(agent, root: root)
        let baseSnapshot: AgentIntegrationSnapshot

        switch agent {
        case .claude:
            let manager = ClaudeCodeHookManager(claudeConfigURL: root, fileManager: fileManager)
            let events = claudeEvents(from: manager.installedHookNames())
            baseSnapshot = AgentIntegrationSnapshot(
                agent: agent,
                status: events.isEmpty ? (detected ? .available : .unavailable) : .installed,
                resolvedDirectory: root,
                integrationFile: manager.settingsPath,
                enabledEvents: events,
                isDetected: detected,
                isInstalled: !events.isEmpty
            )
        case .codex:
            let manager = CodexHookManager(codexHomeURL: root, fileManager: fileManager)
            let events = codexEvents(from: manager.installedHookNames())
            baseSnapshot = AgentIntegrationSnapshot(
                agent: agent,
                status: events.isEmpty ? (detected ? .available : .unavailable) : .installed,
                resolvedDirectory: root,
                integrationFile: manager.hooksPath,
                enabledEvents: events,
                isDetected: detected,
                isInstalled: !events.isEmpty
            )
        case .pi, .omp, .opencode:
            let manager = ManagedAgentIntegrationManager(
                agent: agent,
                rootDirectory: root,
                fileManager: fileManager
            )
            baseSnapshot = AgentIntegrationSnapshot(
                agent: agent,
                status: manager.status(currentPort: port, isDetected: detected),
                resolvedDirectory: root,
                integrationFile: manager.integrationFile,
                enabledEvents: manager.installedEvents(),
                isDetected: detected,
                isInstalled: manager.isOwnedFile()
            )
        }

        guard let message = errors[agent] else { return baseSnapshot }
        return AgentIntegrationSnapshot(
            agent: agent,
            status: .error(message),
            resolvedDirectory: baseSnapshot.resolvedDirectory,
            integrationFile: baseSnapshot.integrationFile,
            enabledEvents: baseSnapshot.enabledEvents,
            isDetected: baseSnapshot.isDetected,
            isInstalled: baseSnapshot.isInstalled
        )
    }

    private func install(agent: CodingAgent, events: Set<IntegrationEvent>, port: Int) throws {
        let root = resolvedDirectory(for: agent)
        switch agent {
        case .claude:
            let manager = ClaudeCodeHookManager(claudeConfigURL: root, fileManager: fileManager)
            try configureClaude(manager, events: events, port: port)
        case .codex:
            let manager = CodexHookManager(codexHomeURL: root, fileManager: fileManager)
            try configureCodex(manager, events: events, port: port)
        case .pi, .omp, .opencode:
            try ManagedAgentIntegrationManager(
                agent: agent,
                rootDirectory: root,
                fileManager: fileManager
            ).install(events: events, port: port)
        }
    }

    private func uninstall(agent: CodingAgent) throws {
        let root = resolvedDirectory(for: agent)
        switch agent {
        case .claude:
            try ClaudeCodeHookManager(claudeConfigURL: root, fileManager: fileManager).uninstallHooks()
        case .codex:
            try CodexHookManager(codexHomeURL: root, fileManager: fileManager).uninstallHooks()
        case .pi, .omp, .opencode:
            try ManagedAgentIntegrationManager(
                agent: agent,
                rootDirectory: root,
                fileManager: fileManager
            ).uninstall()
        }
    }

    private func configureClaude(
        _ manager: ClaudeCodeHookManager,
        events: Set<IntegrationEvent>,
        port: Int
    ) throws {
        let mapping: [(IntegrationEvent, String)] = [
            (.completion, "stop"),
            (.attention, "notification"),
            (.sessionEnd, "session-end")
        ]
        for (event, hook) in mapping {
            if events.contains(event) {
                try manager.installHook(name: hook, port: port)
            } else {
                try manager.uninstallHook(name: hook)
            }
        }
    }

    private func configureCodex(
        _ manager: CodexHookManager,
        events: Set<IntegrationEvent>,
        port: Int
    ) throws {
        let mapping: [(IntegrationEvent, String)] = [
            (.completion, "stop"),
            (.permission, "permission-request"),
            (.subagentCompletion, "subagent-stop")
        ]
        for (event, hook) in mapping {
            if events.contains(event) {
                try manager.installHook(name: hook, port: port)
            } else {
                try manager.uninstallHook(name: hook)
            }
        }
    }

    private func claudeEvents(from hooks: Set<String>) -> Set<IntegrationEvent> {
        var events = Set<IntegrationEvent>()
        if hooks.contains("stop") { events.insert(.completion) }
        if hooks.contains("notification") { events.insert(.attention) }
        if hooks.contains("session-end") { events.insert(.sessionEnd) }
        return events
    }

    private func codexEvents(from hooks: Set<String>) -> Set<IntegrationEvent> {
        var events = Set<IntegrationEvent>()
        if hooks.contains("stop") { events.insert(.completion) }
        if hooks.contains("permission-request") { events.insert(.permission) }
        if hooks.contains("subagent-stop") { events.insert(.subagentCompletion) }
        return events
    }

    private func resolvedDirectory(for agent: CodingAgent) -> URL {
        if let customPath = userDefaults.string(forKey: pathOverrideKey(for: agent)), !customPath.isEmpty {
            return URL(fileURLWithPath: customPath, isDirectory: true).standardizedFileURL
        }

        let environmentKey: String?
        switch agent {
        case .claude: environmentKey = "CLAUDE_CONFIG_DIR"
        case .codex: environmentKey = "CODEX_HOME"
        case .pi, .omp: environmentKey = "PI_CODING_AGENT_DIR"
        case .opencode: environmentKey = "OPENCODE_CONFIG_DIR"
        }
        if let environmentKey,
           let environmentPath = environment[environmentKey],
           !environmentPath.isEmpty {
            return expandedURL(environmentPath)
        }

        switch agent {
        case .claude: return homeDirectoryURL.appendingPathComponent(".claude", isDirectory: true)
        case .codex: return homeDirectoryURL.appendingPathComponent(".codex", isDirectory: true)
        case .pi: return homeDirectoryURL.appendingPathComponent(".pi/agent", isDirectory: true)
        case .omp: return homeDirectoryURL.appendingPathComponent(".omp/agent", isDirectory: true)
        case .opencode: return homeDirectoryURL.appendingPathComponent(".config/opencode", isDirectory: true)
        }
    }

    private func expandedURL(_ path: String) -> URL {
        if path == "~" { return homeDirectoryURL }
        if path.hasPrefix("~/") {
            return homeDirectoryURL.appendingPathComponent(String(path.dropFirst(2)), isDirectory: true)
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private func isDetected(_ agent: CodingAgent, root: URL) -> Bool {
        if fileManager.fileExists(atPath: root.path) { return true }
        return executableCandidates(named: agent.executableName).contains {
            fileManager.isExecutableFile(atPath: $0.path)
        }
    }

    private func executableCandidates(named name: String) -> [URL] {
        var directories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }
        directories.append(contentsOf: [
            homeDirectoryURL.appendingPathComponent(".local/bin", isDirectory: true),
            homeDirectoryURL.appendingPathComponent(".bun/bin", isDirectory: true),
            homeDirectoryURL.appendingPathComponent(".cargo/bin", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/bin", isDirectory: true)
        ])
        return Array(Set(directories.map(\.standardizedFileURL))).map {
            $0.appendingPathComponent(name)
        }
    }

    private func pathOverrideKey(for agent: CodingAgent) -> String {
        "integrationPath.\(agent.rawValue)"
    }
}
