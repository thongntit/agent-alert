import Foundation
import SwiftUI
import Combine

private let cliProxyFractionalSecondsFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let cliProxyISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private enum CLIProxyDefaultsKeys {
    static let baseURL = "cliProxyBaseURL"
    static let pollingEnabled = "cliProxyPollingEnabled"
    static let pollingInterval = "cliProxyPollingInterval"
    static let connectOnLaunch = "cliProxyConnectOnLaunch"
}

private struct CLIProxyAccountCooldown {
    let retryAt: Date
    let attemptCount: Int
}

enum CLIProxyConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(message: String)

    var displayText: String {
        switch self {
        case .disconnected:
            return "CLIProxy: Not configured"
        case .connecting:
            return "CLIProxy: Refreshing"
        case .connected:
            return "CLIProxy: Connected"
        case .error(let message):
            return "CLIProxy: Error - \(message)"
        }
    }
}

@MainActor
final class CLIProxyUsageService: ObservableObject {
    static let shared = CLIProxyUsageService()

    @Published private(set) var status: CLIProxyConnectionStatus = .disconnected
    @Published private(set) var snapshot: CLIProxyUsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasManagementKey = false
    @Published private(set) var discoveredAccounts: [CLIProxyDiscoveredAccount] = []

    @Published var baseURL: String
    @Published var pollingEnabled: Bool
    @Published var pollingInterval: TimeInterval
    @Published var connectOnLaunch: Bool

    private let defaults: UserDefaults
    private let keychainService: KeychainService
    private let session: URLSession
    private var pollingTimer: Timer?
    private var cachedUsagesByAccountID: [String: CLIProxyAccountUsage] = [:]
    private var cooldownsByAccountID: [String: CLIProxyAccountCooldown] = [:]

    private init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared
    ) {
        self.defaults = defaults
        self.keychainService = KeychainService()
        self.session = session
        self.baseURL = defaults.string(forKey: CLIProxyDefaultsKeys.baseURL) ?? ""
        self.pollingEnabled = defaults.object(forKey: CLIProxyDefaultsKeys.pollingEnabled) as? Bool ?? false
        self.pollingInterval = defaults.object(forKey: CLIProxyDefaultsKeys.pollingInterval) as? Double ?? 60
        self.connectOnLaunch = defaults.object(forKey: CLIProxyDefaultsKeys.connectOnLaunch) as? Bool ?? false
        self.hasManagementKey = !(keychainService.loadCLIProxyManagementKey() ?? "").isEmpty

        AppLogger.shared.info("CLIProxy usage service initialized", category: .http)
        updateStatusForCurrentConfiguration()
    }

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasManagementKey
    }

    var supportedAccountCount: Int {
        discoveredAccounts.filter(\.supportsUsageFetch).count
    }

    func loadManagementKey() -> String {
        keychainService.loadCLIProxyManagementKey() ?? ""
    }

    func saveManagementKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if trimmed.isEmpty {
                keychainService.deleteCLIProxyManagementKey()
                hasManagementKey = false
            } else {
                try keychainService.saveCLIProxyManagementKey(trimmed)
                hasManagementKey = true
            }
            errorMessage = nil
            updateStatusForCurrentConfiguration()
            restartPollingIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
            status = .error(message: "Failed to save management key")
        }
    }

    func updateBaseURL(_ newValue: String) {
        baseURL = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(baseURL, forKey: CLIProxyDefaultsKeys.baseURL)
        updateStatusForCurrentConfiguration()
        restartPollingIfNeeded()
    }

    func updatePolling(enabled: Bool, interval: TimeInterval) {
        pollingEnabled = enabled
        pollingInterval = interval
        defaults.set(enabled, forKey: CLIProxyDefaultsKeys.pollingEnabled)
        defaults.set(interval, forKey: CLIProxyDefaultsKeys.pollingInterval)
        restartPollingIfNeeded()
    }

    func updateConnectOnLaunch(_ enabled: Bool) {
        connectOnLaunch = enabled
        defaults.set(enabled, forKey: CLIProxyDefaultsKeys.connectOnLaunch)
    }

    func testConnection() async {
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }

        guard let authFilesRequest = makeAuthFilesRequest() else {
            AppLogger.shared.warning("CLIProxy refresh skipped because configuration is incomplete", category: .http)
            updateStatusForCurrentConfiguration()
            return
        }

        isRefreshing = true
        status = .connecting
        errorMessage = nil
        AppLogger.shared.info("CLIProxy refresh started", category: .http)

        defer {
            isRefreshing = false
        }

        do {
            let authEntries = try await fetchAuthFiles(with: authFilesRequest)
            let accounts = authEntries.map(CLIProxyDiscoveredAccount.init(entry:))
                .sorted { lhs, rhs in
                    if lhs.providerDisplayName != rhs.providerDisplayName {
                        return lhs.providerDisplayName < rhs.providerDisplayName
                    }
                    return lhs.label < rhs.label
                }
            discoveredAccounts = accounts
            let now = Date()
            var usages: [CLIProxyAccountUsage] = []

            for account in accounts where account.isUsable {
                if let cooldown = cooldownsByAccountID[account.id], cooldown.retryAt > now {
                    usages.append(CLIProxyUsageSnapshot.cooldown(
                        account: account,
                        retryAt: cooldown.retryAt,
                        message: "Rate limited",
                        preserving: cachedUsagesByAccountID[account.id]
                    ))
                    continue
                }

                do {
                    let usage: CLIProxyAccountUsage
                    switch account.provider {
                    case .anthropic:
                        usage = try await fetchAnthropicUsage(for: account)
                    case .codex:
                        usage = try await fetchCodexUsage(for: account)
                    case .unsupported:
                        usage = CLIProxyUsageSnapshot.unsupported(account: account, message: "Usage not supported for \(account.providerKey)")
                    }
                    cachedUsagesByAccountID[account.id] = usage
                    cooldownsByAccountID.removeValue(forKey: account.id)
                    usages.append(usage)
                } catch let error as CLIProxyUsageError {
                    if case .upstreamRateLimited(let retryAfter, let headers) = error {
                        let retryAt = computeCooldownRetryDate(for: account, retryAfter: retryAfter, headers: headers)
                        let previous = cachedUsagesByAccountID[account.id]
                        let cooldownUsage = CLIProxyUsageSnapshot.cooldown(
                            account: account,
                            retryAt: retryAt,
                            message: "Rate limited",
                            preserving: previous
                        )
                        let previousAttempts = cooldownsByAccountID[account.id]?.attemptCount ?? 0
                        cooldownsByAccountID[account.id] = CLIProxyAccountCooldown(retryAt: retryAt, attemptCount: previousAttempts + 1)
                        usages.append(cooldownUsage)
                        AppLogger.shared.warning("CLIProxy usage for \(account.label) rate limited until \(retryAt.formatted(date: .omitted, time: .shortened))", category: .http)
                    } else {
                        usages.append(cachedUsagesByAccountID[account.id] ?? CLIProxyUsageSnapshot.failed(account: account, message: error.localizedDescription))
                        AppLogger.shared.error("CLIProxy usage failed for \(account.label): \(error.localizedDescription)", category: .http)
                    }
                } catch {
                    usages.append(cachedUsagesByAccountID[account.id] ?? CLIProxyUsageSnapshot.failed(account: account, message: error.localizedDescription))
                    AppLogger.shared.error("CLIProxy usage failed for \(account.label): \(error.localizedDescription)", category: .http)
                }
            }

            snapshot = CLIProxyUsageSnapshot(accounts: usages)
            status = .connected
            lastUpdated = Date()
            errorMessage = accounts.isEmpty ? "No accounts found" : nil
            AppLogger.shared.info("CLIProxy refresh completed with \(usages.count) account result(s)", category: .http)
        } catch {
            let message = (error as? CLIProxyUsageError)?.localizedDescription ?? error.localizedDescription
            errorMessage = message
            status = .error(message: message)
            AppLogger.shared.error("CLIProxy refresh failed: \(message)", category: .http)
        }
    }

    func startPollingIfNeeded() {
        guard pollingEnabled, isConfigured else {
            stopPolling()
            return
        }

        stopPolling()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        AppLogger.shared.info("CLIProxy polling started every \(Int(pollingInterval))s", category: .http)
        Task {
            await refresh()
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func restartPollingIfNeeded() {
        if pollingEnabled {
            startPollingIfNeeded()
        } else {
            stopPolling()
        }
    }

    private func updateStatusForCurrentConfiguration() {
        if isRefreshing { return }
        if !isConfigured {
            status = .disconnected
        } else if snapshot != nil || !discoveredAccounts.isEmpty {
            status = .connected
        } else if case .error = status {
            return
        } else {
            status = .disconnected
        }
    }

    private func fetchAuthFiles(with request: URLRequest) async throws -> [CLIProxyAuthFileEntry] {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIProxyUsageError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CLIProxyUsageError.managementRequestFailed(statusCode: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(CLIProxyAuthFilesResponse.self, from: data).files
    }

    private func fetchAnthropicUsage(for account: CLIProxyDiscoveredAccount) async throws -> CLIProxyAccountUsage {
        let requestPayload = CLIProxyAPICallRequest(
            authIndex: account.authIndex,
            method: "GET",
            url: "https://api.anthropic.com/api/oauth/usage",
            header: [
                "Authorization": "Bearer $TOKEN$",
                "Content-Type": "application/json",
                "anthropic-beta": "oauth-2025-04-20"
            ],
            data: nil
        )

        let envelope = try await performAPICall(requestPayload)
        let usageData = Data(envelope.body.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = cliProxyFractionalSecondsFormatter.date(from: value) ?? cliProxyISO8601Formatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        let usageResponse = try decoder.decode(AnthropicOAuthUsageResponse.self, from: usageData)
        return CLIProxyUsageSnapshot.anthropic(account: account, response: usageResponse)
    }

    private func fetchCodexUsage(for account: CLIProxyDiscoveredAccount) async throws -> CLIProxyAccountUsage {
        guard let accountID = account.codexAccountID, !accountID.isEmpty else {
            return CLIProxyUsageSnapshot.failed(account: account, message: "Missing ChatGPT account id")
        }

        let requestPayload = CLIProxyAPICallRequest(
            authIndex: account.authIndex,
            method: "GET",
            url: "https://chatgpt.com/backend-api/wham/usage",
            header: [
                "Authorization": "Bearer $TOKEN$",
                "Content-Type": "application/json",
                "User-Agent": "codex_cli_rs/0.76.0 (Debian 13.0.0; x86_64) WindowsTerminal",
                "Chatgpt-Account-Id": accountID
            ],
            data: nil
        )

        let envelope = try await performAPICall(requestPayload)
        let usageData = Data(envelope.body.utf8)
        let decoder = JSONDecoder()
        let response = try decoder.decode(CodexUsageResponse.self, from: usageData)
        let jsonObject = try JSONSerialization.jsonObject(with: usageData)
        let preview = prettyPrintedJSONString(from: jsonObject)
        return CLIProxyUsageSnapshot.codex(account: account, response: response, rawPreview: preview)
    }

    private func performAPICall(_ payload: CLIProxyAPICallRequest) async throws -> CLIProxyAPICallResponse {
        guard let request = makeAPICallRequest(payload: payload) else {
            throw CLIProxyUsageError.invalidConfiguration(message: "Missing CLIProxy configuration")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIProxyUsageError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CLIProxyUsageError.managementRequestFailed(statusCode: httpResponse.statusCode)
        }

        let envelope = try JSONDecoder().decode(CLIProxyAPICallResponse.self, from: data)
        guard (200..<300).contains(envelope.statusCode) else {
            if envelope.statusCode == 429 {
                throw CLIProxyUsageError.upstreamRateLimited(
                    retryAfter: retryAfterSeconds(from: envelope.header),
                    headers: envelope.header
                )
            }
            throw CLIProxyUsageError.upstreamRequestFailed(statusCode: envelope.statusCode)
        }
        return envelope
    }

    private func makeAuthFilesRequest() -> URLRequest? {
        guard let baseURL = validatedBaseURL(), let managementKey = validatedManagementKey() else {
            return nil
        }

        let endpointURL = baseURL.appendingPathComponent("v0/management/auth-files")
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(managementKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func makeAPICallRequest(payload: CLIProxyAPICallRequest) -> URLRequest? {
        guard let baseURL = validatedBaseURL(), let managementKey = validatedManagementKey() else {
            return nil
        }

        let endpointURL = baseURL.appendingPathComponent("v0/management/api-call")
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(managementKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONEncoder().encode(payload)
            return request
        } catch {
            errorMessage = "Failed to encode request"
            status = .error(message: error.localizedDescription)
            return nil
        }
    }

    private func validatedBaseURL() -> URL? {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURL.isEmpty else {
            errorMessage = "Base URL is required"
            return nil
        }
        guard let baseURL = URL(string: trimmedBaseURL) else {
            errorMessage = "Base URL is invalid"
            return nil
        }
        return baseURL
    }

    private func validatedManagementKey() -> String? {
        let trimmedManagementKey = loadManagementKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedManagementKey.isEmpty else {
            errorMessage = "Management key is required"
            return nil
        }
        return trimmedManagementKey
    }

    private func prettyPrintedJSONString(from object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private func retryAfterSeconds(from headers: [String: [String]]) -> TimeInterval? {
        let retryAfterValue = headers.first { $0.key.caseInsensitiveCompare("retry-after") == .orderedSame }?.value.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let retryAfterValue, !retryAfterValue.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(retryAfterValue) {
            return seconds
        }

        if let date = cliProxyISO8601Formatter.date(from: retryAfterValue) {
            return max(0, date.timeIntervalSinceNow)
        }

        return nil
    }

    private func computeCooldownRetryDate(
        for account: CLIProxyDiscoveredAccount,
        retryAfter: TimeInterval?,
        headers: [String: [String]]
    ) -> Date {
        if let retryAfter {
            return Date().addingTimeInterval(max(0, retryAfter))
        }

        let attempts = (cooldownsByAccountID[account.id]?.attemptCount ?? 0) + 1
        let baseSeconds: TimeInterval
        switch account.provider {
        case .anthropic:
            baseSeconds = 300
        case .codex:
            baseSeconds = 600
        case .unsupported:
            baseSeconds = 300
        }

        let multiplier = pow(2.0, Double(max(0, attempts - 1)))
        let cooldown = min(baseSeconds * multiplier, 1800)
        return Date().addingTimeInterval(cooldown)
    }
}

enum CLIProxyUsageError: LocalizedError {
    case invalidConfiguration(message: String)
    case invalidResponse
    case managementRequestFailed(statusCode: Int)
    case upstreamRequestFailed(statusCode: Int)
    case upstreamRateLimited(retryAfter: TimeInterval?, headers: [String: [String]])

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return message
        case .invalidResponse:
            return "Invalid server response"
        case .managementRequestFailed(let statusCode):
            return "CLIProxy returned HTTP \(statusCode)"
        case .upstreamRequestFailed(let statusCode):
            return "Upstream usage request returned HTTP \(statusCode)"
        case .upstreamRateLimited(let retryAfter, _):
            if let retryAfter {
                return "Upstream usage request was rate limited. Retry in \(Int(retryAfter.rounded()))s"
            }
            return "Upstream usage request was rate limited"
        }
    }
}
