import Foundation

struct CLIProxyAPICallRequest: Encodable {
    let authIndex: String
    let method: String
    let url: String
    let header: [String: String]
    let data: String?
}

struct CLIProxyAPICallResponse: Decodable {
    let statusCode: Int
    let header: [String: [String]]
    let body: String

    private enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case header
        case body
    }
}

struct CLIProxyAuthFilesResponse: Decodable {
    let files: [CLIProxyAuthFileEntry]
}

struct CLIProxyAuthFileEntry: Decodable {
    let authIndex: String
    let provider: String
    let label: String?
    let status: String?
    let statusMessage: String?
    let disabled: Bool?
    let unavailable: Bool?
    let email: String?
    let account: String?
    let idToken: CLIProxyCodexIDToken?

    private enum CodingKeys: String, CodingKey {
        case authIndex = "auth_index"
        case provider
        case label
        case status
        case statusMessage = "status_message"
        case disabled
        case unavailable
        case email
        case account
        case idToken = "id_token"
    }
}

struct CLIProxyCodexIDToken: Decodable {
    let chatgptAccountID: String?
    let planType: String?

    private enum CodingKeys: String, CodingKey {
        case chatgptAccountID = "chatgpt_account_id"
        case planType = "plan_type"
    }
}

enum CLIProxyUsageProvider: String {
    case anthropic
    case codex
    case unsupported

    var displayName: String {
        switch self {
        case .anthropic:
            return "Anthropic"
        case .codex:
            return "Codex"
        case .unsupported:
            return "Unsupported"
        }
    }
}

struct CLIProxyDiscoveredAccount: Identifiable {
    let id: String
    let provider: CLIProxyUsageProvider
    let providerKey: String
    let authIndex: String
    let label: String
    let detail: String?
    let status: String?
    let statusMessage: String?
    let isUsable: Bool
    let codexAccountID: String?

    var providerDisplayName: String {
        provider.displayName
    }

    var supportsUsageFetch: Bool {
        provider != .unsupported && isUsable
    }
}

struct AnthropicUsageBucket: Decodable {
    let utilization: Double?
    let resetsAt: Date?
    let limitDollars: Double?
    let usedDollars: Double?
    let remainingDollars: Double?

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
        case limitDollars = "limit_dollars"
        case usedDollars = "used_dollars"
        case remainingDollars = "remaining_dollars"
    }

    var isMeaningful: Bool {
        utilization != nil || resetsAt != nil || limitDollars != nil || usedDollars != nil || remainingDollars != nil
    }
}

struct AnthropicUsageLimit: Decodable, Identifiable {
    let kind: String
    let group: String
    let percent: Double?
    let severity: String?
    let resetsAt: Date?
    let scope: String?
    let isActive: Bool

    var id: String {
        [kind, group, scope ?? "global"].joined(separator: ":")
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case group
        case percent
        case severity
        case resetsAt = "resets_at"
        case scope
        case isActive = "is_active"
    }
}

struct AnthropicMoneyAmount: Decodable {
    let amountMinor: Int
    let currency: String
    let exponent: Int

    private enum CodingKeys: String, CodingKey {
        case amountMinor = "amount_minor"
        case currency
        case exponent
    }
}

struct AnthropicSpendInfo: Decodable {
    let used: AnthropicMoneyAmount?
    let limit: AnthropicMoneyAmount?
    let percent: Double?
    let severity: String?
    let enabled: Bool
    let disclaimer: String?

    private enum CodingKeys: String, CodingKey {
        case used
        case limit
        case percent
        case severity
        case enabled
        case disclaimer
    }
}

struct AnthropicOAuthUsageResponse: Decodable {
    let bucketValues: [String: AnthropicUsageBucket?]
    let limits: [AnthropicUsageLimit]
    let spend: AnthropicSpendInfo?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)

        var bucketValues: [String: AnthropicUsageBucket?] = [:]
        var limits: [AnthropicUsageLimit] = []
        var spend: AnthropicSpendInfo?

        for key in container.allKeys {
            switch key.stringValue {
            case "limits":
                limits = try container.decodeIfPresent([AnthropicUsageLimit].self, forKey: key) ?? []
            case "spend":
                spend = try container.decodeIfPresent(AnthropicSpendInfo.self, forKey: key)
            default:
                if (try? container.decodeNil(forKey: key)) == true {
                    bucketValues[key.stringValue] = nil
                } else if let bucket = try? container.decode(AnthropicUsageBucket.self, forKey: key) {
                    bucketValues[key.stringValue] = bucket
                }
            }
        }

        self.bucketValues = bucketValues
        self.limits = limits
        self.spend = spend
    }

    private struct DynamicCodingKeys: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}

struct CodexUsageResponse: Decodable {
    let accountID: String?
    let email: String?
    let planType: String?
    let credits: CodexCredits?
    let rateLimit: CodexRateLimit?
    let rateLimitReachedType: String?
    let rateLimitResetCredits: CodexResetCredits?
    let spendControl: CodexSpendControl?

    private enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case email
        case planType = "plan_type"
        case credits
        case rateLimit = "rate_limit"
        case rateLimitReachedType = "rate_limit_reached_type"
        case rateLimitResetCredits = "rate_limit_reset_credits"
        case spendControl = "spend_control"
    }
}

struct CodexCredits: Decodable {
    let balance: String?
    let hasCredits: Bool?
    let overageLimitReached: Bool?
    let unlimited: Bool?

    private enum CodingKeys: String, CodingKey {
        case balance
        case hasCredits = "has_credits"
        case overageLimitReached = "overage_limit_reached"
        case unlimited
    }
}

struct CodexRateLimit: Decodable {
    let allowed: Bool?
    let limitReached: Bool?
    let primaryWindow: CodexRateLimitWindow?
    let secondaryWindow: CodexRateLimitWindow?

    private enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

struct CodexRateLimitWindow: Decodable {
    let limitWindowSeconds: Int?
    let resetAfterSeconds: Int?
    let resetAt: TimeInterval?
    let usedPercent: Double?

    private enum CodingKeys: String, CodingKey {
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
        case usedPercent = "used_percent"
    }

    nonisolated var resetDate: Date? {
        guard let resetAt else { return nil }
        return Date(timeIntervalSince1970: resetAt)
    }
}

struct CodexResetCredits: Decodable {
    let availableCount: Int?

    private enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
    }
}

struct CodexSpendControl: Decodable {
    let reached: Bool?
}

struct CLIProxyUsageSnapshot {
    let accounts: [CLIProxyAccountUsage]

    var activeLimits: [CLIProxyActiveLimitSummary] {
        accounts.flatMap(\.activeLimits)
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive && !rhs.isActive
                }
                return (lhs.percent ?? 0) > (rhs.percent ?? 0)
            }
    }

    var menuLines: [String] {
        accounts.compactMap(\.menuLine)
    }
}

struct CLIProxyAccountUsage: Identifiable {
    let id: String
    let provider: CLIProxyUsageProvider
    let accountLabel: String
    let accountDetail: String?
    let state: CLIProxyAccountUsageState
    let bucketSummaries: [CLIProxyUsageBucketSummary]
    let activeLimits: [CLIProxyActiveLimitSummary]
    let spendSummary: CLIProxySpendSummary?
    let summaryLines: [String]
    let rawResponsePreview: String?

    var menuLine: String? {
        switch state {
        case .cooldown(let retryAt, _):
            return accountLabel + " · retry in " + retryAt.formatted(.relative(presentation: .named))
        case .unsupported(let message):
            return accountLabel + " · " + message
        case .failed(let message):
            return accountLabel + " · " + message
        case .success:
            if let firstLimit = activeLimits.first {
                let prefix = accountLabel + " · " + firstLimit.title + ": "
                let percent = firstLimit.percent.map { String(format: "%.0f%% used", $0) } ?? "No usage"
                if let resetsAt = firstLimit.resetsAt {
                    return prefix + percent + " · resets " + resetsAt.formatted(date: .abbreviated, time: .shortened)
                }
                return prefix + percent
            }

            if let firstSummary = summaryLines.first {
                return accountLabel + " · " + firstSummary
            }

            return nil
        }
    }
}

enum CLIProxyAccountUsageState: Equatable {
    case success
    case cooldown(retryAt: Date, message: String)
    case unsupported(message: String)
    case failed(message: String)
}

struct CLIProxyUsageBucketSummary: Identifiable {
    let id: String
    let title: String
    let utilizationPercent: Double?
    let remainingPercent: Double?
    let resetsAt: Date?
    let remainingDollars: Double?
}

struct CLIProxyActiveLimitSummary: Identifiable {
    let id: String
    let kind: String
    let group: String
    let percent: Double?
    let severity: String?
    let resetsAt: Date?
    let isActive: Bool

    var title: String {
        switch group {
        case "weekly":
            return "Weekly"
        case "session":
            return "Session"
        default:
            return group.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct CLIProxySpendSummary {
    let enabled: Bool
    let usedDisplay: String?
    let limitDisplay: String?
    let percent: Double?
    let disclaimer: String?
}

enum CLIProxyJSONValue {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: CLIProxyJSONValue])
    case array([CLIProxyJSONValue])
    case null
}

extension CLIProxyDiscoveredAccount {
    init(entry: CLIProxyAuthFileEntry) {
        let providerKey = entry.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let provider: CLIProxyUsageProvider
        if providerKey.contains("claude") || providerKey.contains("anthropic") {
            provider = .anthropic
        } else if providerKey.contains("codex") {
            provider = .codex
        } else {
            provider = .unsupported
        }

        let detail = entry.email ?? entry.account ?? entry.idToken?.planType
        let label = entry.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLabel = (label?.isEmpty == false ? label! : nil) ?? detail ?? provider.displayName
        let statusMessage = entry.statusMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let disabled = entry.disabled ?? false
        let unavailable = entry.unavailable ?? false

        self.id = entry.authIndex
        self.provider = provider
        self.providerKey = providerKey
        self.authIndex = entry.authIndex
        self.label = normalizedLabel
        self.detail = detail
        self.status = entry.status
        self.statusMessage = statusMessage
        self.isUsable = !disabled && !unavailable
        self.codexAccountID = entry.idToken?.chatgptAccountID
    }
}

extension CLIProxyUsageSnapshot {
    static func anthropic(account: CLIProxyDiscoveredAccount, response: AnthropicOAuthUsageResponse) -> CLIProxyAccountUsage {
        let bucketSummaries = response.bucketValues
            .compactMap { (entry: (key: String, value: AnthropicUsageBucket?)) -> CLIProxyUsageBucketSummary? in
                guard let bucket = entry.value, bucket.isMeaningful else { return nil }
                let utilization = bucket.utilization
                return CLIProxyUsageBucketSummary(
                    id: entry.key,
                    title: humanizeBucketName(entry.key),
                    utilizationPercent: utilization,
                    remainingPercent: utilization.map { max(0, 100 - $0) },
                    resetsAt: bucket.resetsAt,
                    remainingDollars: bucket.remainingDollars
                )
            }
            .sorted { $0.title < $1.title }

        let activeLimits = response.limits
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive && !rhs.isActive
                }
                return (lhs.percent ?? 0) > (rhs.percent ?? 0)
            }
            .map {
                CLIProxyActiveLimitSummary(
                    id: $0.id,
                    kind: $0.kind,
                    group: $0.group,
                    percent: $0.percent,
                    severity: $0.severity,
                    resetsAt: $0.resetsAt,
                    isActive: $0.isActive
                )
            }

        let spendSummary = response.spend.map {
            CLIProxySpendSummary(
                enabled: $0.enabled,
                usedDisplay: $0.used.map(moneyString),
                limitDisplay: $0.limit.map(moneyString),
                percent: $0.percent,
                disclaimer: $0.disclaimer
            )
        }

        let summaryLines = activeLimits.prefix(2).map { limit in
            let percent = limit.percent.map { String(format: "%.0f%% used", $0) } ?? "No usage"
            if let resetsAt = limit.resetsAt {
                return limit.title + ": " + percent + " · resets " + resetsAt.formatted(date: .abbreviated, time: .shortened)
            }
            return limit.title + ": " + percent
        }

        return CLIProxyAccountUsage(
            id: account.id,
            provider: account.provider,
            accountLabel: account.label,
            accountDetail: account.detail,
            state: .success,
            bucketSummaries: bucketSummaries,
            activeLimits: activeLimits,
            spendSummary: spendSummary,
            summaryLines: summaryLines,
            rawResponsePreview: nil
        )
    }

    static func codex(account: CLIProxyDiscoveredAccount, response: CodexUsageResponse, rawPreview: String?) -> CLIProxyAccountUsage {
        let primary = response.rateLimit?.primaryWindow
        let secondary = response.rateLimit?.secondaryWindow

        let bucketSummaries = [
            codexBucketSummary(id: "primary_window", title: "5 Hour", window: primary),
            codexBucketSummary(id: "secondary_window", title: "7 Day", window: secondary)
        ].compactMap { $0 }

        let activeLimits = [
            codexLimitSummary(id: "primary_window", group: "session", window: primary),
            codexLimitSummary(id: "secondary_window", group: "weekly", window: secondary)
        ].compactMap { $0 }

        var summaryLines: [String] = []
        if let planType = response.planType {
            summaryLines.append("Plan: " + planType.capitalized)
        }
        if let credits = response.credits {
            if credits.unlimited == true {
                summaryLines.append("Credits: Unlimited")
            } else if let balance = credits.balance {
                summaryLines.append("Credits balance: " + balance)
            }
            if let availableCount = response.rateLimitResetCredits?.availableCount {
                summaryLines.append("Reset credits available: \(availableCount)")
            }
        }
        if response.rateLimit?.allowed == false || response.rateLimit?.limitReached == true {
            summaryLines.append("Rate limited")
        }

        return CLIProxyAccountUsage(
            id: account.id,
            provider: account.provider,
            accountLabel: account.label,
            accountDetail: response.email ?? account.detail,
            state: .success,
            bucketSummaries: bucketSummaries,
            activeLimits: activeLimits,
            spendSummary: nil,
            summaryLines: summaryLines,
            rawResponsePreview: rawPreview
        )
    }

    static func unsupported(account: CLIProxyDiscoveredAccount, message: String) -> CLIProxyAccountUsage {
        CLIProxyAccountUsage(
            id: account.id,
            provider: account.provider,
            accountLabel: account.label,
            accountDetail: account.detail,
            state: .unsupported(message: message),
            bucketSummaries: [],
            activeLimits: [],
            spendSummary: nil,
            summaryLines: [message],
            rawResponsePreview: nil
        )
    }

    static func failed(account: CLIProxyDiscoveredAccount, message: String) -> CLIProxyAccountUsage {
        CLIProxyAccountUsage(
            id: account.id,
            provider: account.provider,
            accountLabel: account.label,
            accountDetail: account.detail,
            state: .failed(message: message),
            bucketSummaries: [],
            activeLimits: [],
            spendSummary: nil,
            summaryLines: [message],
            rawResponsePreview: nil
        )
    }

    static func cooldown(account: CLIProxyDiscoveredAccount, retryAt: Date, message: String, preserving existing: CLIProxyAccountUsage?) -> CLIProxyAccountUsage {
        CLIProxyAccountUsage(
            id: account.id,
            provider: account.provider,
            accountLabel: existing?.accountLabel ?? account.label,
            accountDetail: existing?.accountDetail ?? account.detail,
            state: .cooldown(retryAt: retryAt, message: message),
            bucketSummaries: existing?.bucketSummaries ?? [],
            activeLimits: existing?.activeLimits ?? [],
            spendSummary: existing?.spendSummary,
            summaryLines: existing?.summaryLines ?? [message],
            rawResponsePreview: existing?.rawResponsePreview
        )
    }

    nonisolated private static func humanizeBucketName(_ key: String) -> String {
        let numberMap: [String: String] = ["five": "5", "seven": "7"]
        return key
            .split(separator: "_")
            .map { numberMap[String($0)] ?? String($0) }
            .joined(separator: " ")
            .capitalized
    }

    nonisolated private static func moneyString(_ amount: AnthropicMoneyAmount) -> String {
        let divisor = pow(10.0, Double(amount.exponent))
        let value = Double(amount.amountMinor) / divisor
        return amount.currency + " " + String(format: "%.2f", value)
    }

    nonisolated private static func codexBucketSummary(id: String, title: String, window: CodexRateLimitWindow?) -> CLIProxyUsageBucketSummary? {
        guard let window, let usedPercent = window.usedPercent else { return nil }
        return CLIProxyUsageBucketSummary(
            id: id,
            title: title,
            utilizationPercent: usedPercent,
            remainingPercent: max(0, 100 - usedPercent),
            resetsAt: window.resetDate,
            remainingDollars: nil
        )
    }

    nonisolated private static func codexLimitSummary(id: String, group: String, window: CodexRateLimitWindow?) -> CLIProxyActiveLimitSummary? {
        guard let window, let usedPercent = window.usedPercent else { return nil }
        return CLIProxyActiveLimitSummary(
            id: id,
            kind: group == "session" ? "session" : "weekly_all",
            group: group,
            percent: usedPercent,
            severity: usedPercent >= 90 ? "high" : usedPercent >= 75 ? "medium" : "normal",
            resetsAt: window.resetDate,
            isActive: true
        )
    }

    nonisolated private static func jsonValue(from object: Any) -> CLIProxyJSONValue {
        switch object {
        case let value as String:
            return .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            return .number(value.doubleValue)
        case let value as [String: Any]:
            return .object(value.mapValues(jsonValue(from:)))
        case let value as [Any]:
            return .array(value.map(jsonValue(from:)))
        default:
            return .null
        }
    }

    nonisolated private static func summarizeCodexUsage(_ value: CLIProxyJSONValue, prefix: String = "") -> [String] {
        let interestingKeys = ["usage", "used", "remaining", "limit", "reset", "percent", "quota", "cap"]

        switch value {
        case .object(let object):
            var lines: [String] = []
            for key in object.keys.sorted() {
                let child = object[key]!
                let keyPrefix = prefix.isEmpty ? key : prefix + "." + key
                let normalized = key.lowercased()
                switch child {
                case .string(let stringValue):
                    if interestingKeys.contains(where: { normalized.contains($0) }) {
                        lines.append(humanizeCodexKey(keyPrefix) + ": " + stringValue)
                    }
                case .number(let numberValue):
                    if interestingKeys.contains(where: { normalized.contains($0) }) {
                        let formatted = abs(numberValue.rounded() - numberValue) < 0.001
                            ? String(Int(numberValue.rounded()))
                            : String(format: "%.2f", numberValue)
                        lines.append(humanizeCodexKey(keyPrefix) + ": " + formatted)
                    }
                case .bool(let boolValue):
                    if interestingKeys.contains(where: { normalized.contains($0) }) {
                        lines.append(humanizeCodexKey(keyPrefix) + ": " + (boolValue ? "Yes" : "No"))
                    }
                case .object, .array:
                    lines.append(contentsOf: summarizeCodexUsage(child, prefix: keyPrefix))
                case .null:
                    continue
                }
            }
            return Array(lines.prefix(6))
        case .array(let values):
            return values.flatMap { summarizeCodexUsage($0, prefix: prefix) }
        default:
            return []
        }
    }

    nonisolated private static func humanizeCodexKey(_ key: String) -> String {
        key
            .replacingOccurrences(of: ".", with: " · ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
