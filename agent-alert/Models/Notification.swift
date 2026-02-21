import Foundation

enum NotificationSource: String, Codable {
    case claude = "claude"
    case opencode = "opencode"
    
    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .opencode: return "OpenCode"
        }
    }
    
    var icon: String {
        switch self {
        case .claude: return "brain.head.profile"
        case .opencode: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum NotificationType: String, Codable {
    case complete = "complete"
    case permission = "permission"
    case question = "question"
    case idle = "idle"
    
    var color: String {
        switch self {
        case .complete: return "#4ECDC4"
        case .permission: return "#FFE66D"
        case .question: return "#95E1D3"
        case .idle: return "#F38181"
        }
    }
    
    var icon: String {
        switch self {
        case .complete: return "checkmark.circle.fill"
        case .permission: return "lock.shield.fill"
        case .question: return "questionmark.circle.fill"
        case .idle: return "clock.fill"
        }
    }
}

struct AgenticNotification: Identifiable, Codable {
    let id = UUID()
    let source: NotificationSource
    let type: NotificationType
    let message: String
    let timestamp: Date
    var isRead: Bool = false
    
    init(source: NotificationSource, type: NotificationType, message: String) {
        self.source = source
        self.type = type
        self.message = message
        self.timestamp = Date()
    }
}
