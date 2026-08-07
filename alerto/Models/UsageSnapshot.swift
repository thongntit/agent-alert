import Foundation

enum UsageProvider: String, CaseIterable, Identifiable, Hashable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var icon: String {
        switch self {
        case .claude: return "brain.head.profile"
        case .codex: return "terminal.fill"
        }
    }
}

struct UsageSnapshot: Equatable {
    let generatedAt: Date
    var providers: [ProviderUsage]

    func usage(for provider: UsageProvider) -> ProviderUsage? {
        providers.first { $0.provider == provider }
    }

    mutating func replace(_ usage: ProviderUsage) {
        if let index = providers.firstIndex(where: { $0.provider == usage.provider }) {
            providers[index] = usage
        } else {
            providers.append(usage)
        }
    }

    mutating func markStale(_ provider: UsageProvider) {
        guard let index = providers.firstIndex(where: { $0.provider == provider }) else { return }
        providers[index].isStale = true
    }
}

struct ProviderUsage: Identifiable, Equatable {
    let provider: UsageProvider
    let plan: String?
    var isStale: Bool
    let limits: [UsageLimit]

    var id: String { provider.rawValue }
}

struct UsageLimit: Identifiable, Equatable {
    let label: String
    let remainingPercent: Double
    let resetsAt: Date?

    var id: String { label }

    var formattedRemaining: String {
        "\(Int(remainingPercent.rounded()))% left"
    }
}

enum UsageFetchError: LocalizedError, Equatable {
    case notSignedIn(UsageProvider)
    case keychainAccessRequired
    case sessionExpired(UsageProvider)
    case requestFailed(UsageProvider, Int)
    case invalidResponse(UsageProvider)
    case connectionFailed(UsageProvider)

    var errorDescription: String? {
        switch self {
        case .notSignedIn(let provider):
            return "Sign in to \(provider.displayName) to show usage."
        case .keychainAccessRequired:
            return "Allow Alerto to read the Claude Code login in Keychain, then refresh."
        case .sessionExpired(let provider):
            return "\(provider.displayName) session expired. Sign in again, then refresh."
        case .requestFailed(let provider, let status):
            return "\(provider.displayName) usage request failed (HTTP \(status))."
        case .invalidResponse(let provider):
            return "\(provider.displayName) returned invalid usage data."
        case .connectionFailed(let provider):
            return "Couldn't reach \(provider.displayName)."
        }
    }
}

enum UsageResponseMapper {
    static func claude(data: Data) throws -> ProviderUsage {
        guard let body = try jsonObject(data) else {
            throw UsageFetchError.invalidResponse(.claude)
        }

        let limits = [
            limit(label: "Session", body: body["five_hour"]),
            limit(label: "Weekly", body: body["seven_day"])
        ].compactMap { $0 }

        guard !limits.isEmpty else {
            throw UsageFetchError.invalidResponse(.claude)
        }
        return ProviderUsage(provider: .claude, plan: nil, isStale: false, limits: limits)
    }

    static func codex(data: Data, now: Date = Date()) throws -> ProviderUsage {
        guard let body = try jsonObject(data) else {
            throw UsageFetchError.invalidResponse(.codex)
        }

        let rateLimit = body["rate_limit"] as? [String: Any]
        let candidates = [
            window(body: rateLimit?["primary_window"], fallback: .session),
            window(body: rateLimit?["secondary_window"], fallback: .weekly)
        ].compactMap { $0 }

        let limits = [
            classifiedLimit(label: "Session", kind: .session, windows: candidates, now: now),
            classifiedLimit(label: "Weekly", kind: .weekly, windows: candidates, now: now)
        ].compactMap { $0 }

        guard !limits.isEmpty else {
            throw UsageFetchError.invalidResponse(.codex)
        }
        return ProviderUsage(
            provider: .codex,
            plan: formattedPlan(body["plan_type"] as? String),
            isStale: false,
            limits: limits
        )
    }

    private enum WindowKind {
        case session
        case weekly
    }

    private struct Window {
        let body: [String: Any]
        let usedPercent: Double
        let fallback: WindowKind
    }

    private static func window(body: Any?, fallback: WindowKind) -> Window? {
        guard let body = body as? [String: Any],
              let usedPercent = number(body["used_percent"])
        else {
            return nil
        }
        return Window(body: body, usedPercent: usedPercent, fallback: fallback)
    }

    private static func classifiedLimit(
        label: String,
        kind: WindowKind,
        windows: [Window],
        now: Date
    ) -> UsageLimit? {
        let matching = windows.first { classification(of: $0.body) == kind }
        let fallback = windows.first { classification(of: $0.body) == nil && $0.fallback == kind }
        guard let window = matching ?? fallback else { return nil }

        return UsageLimit(
            label: label,
            remainingPercent: boundedRemaining(fromUsed: window.usedPercent),
            resetsAt: resetDate(window.body, now: now)
        )
    }

    private static func classification(of body: [String: Any]) -> WindowKind? {
        guard let seconds = number(body["limit_window_seconds"]) else { return nil }
        // Codex's session window is currently five hours, while the other standard window is weekly.
        // Treat anything shorter than two days as a session to tolerate a changed short window.
        return seconds < 2 * 24 * 60 * 60 ? .session : .weekly
    }

    private static func limit(label: String, body: Any?) -> UsageLimit? {
        guard let body = body as? [String: Any],
              let usedPercent = number(body["utilization"])
        else {
            return nil
        }
        return UsageLimit(
            label: label,
            remainingPercent: boundedRemaining(fromUsed: usedPercent),
            resetsAt: resetDate(body, now: Date())
        )
    }

    private static func boundedRemaining(fromUsed used: Double) -> Double {
        min(100, max(0, 100 - used))
    }

    private static func resetDate(_ body: [String: Any], now: Date) -> Date? {
        if let text = body["resets_at"] as? String {
            return ISO8601DateParser.date(from: text)
        }
        if let seconds = number(body["reset_at"]) {
            return Date(timeIntervalSince1970: seconds)
        }
        if let seconds = number(body["reset_after_seconds"]) {
            return now.addingTimeInterval(seconds)
        }
        return nil
    }

    private static func formattedPlan(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any]? {
        try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }
}

enum ISO8601DateParser {
    static func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}
