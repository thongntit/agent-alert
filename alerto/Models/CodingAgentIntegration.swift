import Foundation

enum CodingAgent: String, CaseIterable, Identifiable, Hashable {
    case claude
    case codex
    case pi
    case omp
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .pi: return "Pi"
        case .omp: return "Oh My Pi"
        case .opencode: return "OpenCode"
        }
    }

    var executableName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .pi: return "pi"
        case .omp: return "omp"
        case .opencode: return "opencode"
        }
    }

    var notificationSource: NotificationSource {
        switch self {
        case .claude: return .claude
        case .codex: return .codex
        case .pi: return .pi
        case .omp: return .omp
        case .opencode: return .opencode
        }
    }

    var supportedEvents: [IntegrationEvent] {
        switch self {
        case .claude:
            return [.completion, .attention, .sessionEnd]
        case .codex:
            return [.completion, .permission, .subagentCompletion]
        case .pi:
            return [.completion]
        case .omp, .opencode:
            return [.completion, .permission, .question, .error]
        }
    }

    var defaultEvents: Set<IntegrationEvent> { Set(supportedEvents) }
}

enum IntegrationEvent: String, CaseIterable, Identifiable, Hashable {
    case completion
    case attention
    case permission
    case question
    case error
    case subagentCompletion = "subagent-completion"
    case sessionEnd = "session-end"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .completion: return "Task completion"
        case .attention: return "Attention needed"
        case .permission: return "Permission requests"
        case .question: return "Questions and input"
        case .error: return "Errors"
        case .subagentCompletion: return "Subagent completion"
        case .sessionEnd: return "Session end"
        }
    }
}

enum AgentIntegrationStatus: Equatable {
    case unavailable
    case available
    case installed
    case updateRequired
    case conflict
    case error(String)

    var displayText: String {
        switch self {
        case .unavailable: return "Not detected"
        case .available: return "Available"
        case .installed: return "Enabled"
        case .updateRequired: return "Update required"
        case .conflict: return "File conflict"
        case .error: return "Error"
        }
    }
}

struct AgentIntegrationSnapshot: Equatable {
    let agent: CodingAgent
    let status: AgentIntegrationStatus
    let resolvedDirectory: URL
    let integrationFile: URL?
    let enabledEvents: Set<IntegrationEvent>
    let isDetected: Bool
    let isInstalled: Bool

    var isEnabled: Bool { isInstalled }
}
