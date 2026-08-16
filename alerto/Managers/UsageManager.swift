import Foundation
import Combine

/// Refreshes direct, read-only Claude Code and Codex quota requests on a conservative cadence.
@MainActor
final class UsageManager: ObservableObject {
    static let shared = UsageManager()

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var providerErrors: [UsageProvider: String] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?

    private let client: UsageClient
    private var refreshTimer: Timer?
    private var lastAttemptAt: Date?

    init(client: UsageClient = UsageClient()) {
        self.client = client
        startAutomaticRefresh()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    /// Automatic refreshes are spaced five minutes apart. A manual refresh can request Keychain
    /// access if needed, but is still coalesced for 30 seconds to avoid accidental API hammering.
    func refresh(manual: Bool = false) async {
        guard !isRefreshing else { return }
        let now = Date()
        let minimumInterval: TimeInterval = manual ? 30 : 5 * 60
        guard lastAttemptAt.map({ now.timeIntervalSince($0) >= minimumInterval }) ?? true else { return }

        isRefreshing = true
        lastAttemptAt = now
        defer { isRefreshing = false }

        // Usage refreshes must never block the menu bar with a Keychain prompt.
        async let claude = result { try await client.fetchClaude(allowKeychainInteraction: false) }
        async let codex = result { try await client.fetchCodex() }

        let results: [(UsageProvider, Result<ProviderUsage, Error>)] = [
            (.claude, await claude),
            (.codex, await codex)
        ]

        var updated = snapshot ?? UsageSnapshot(generatedAt: now, providers: [])
        var errors: [UsageProvider: String] = [:]
        for (provider, result) in results {
            switch result {
            case .success(let usage):
                updated.replace(usage)
            case .failure(let error):
                updated.markStale(provider)
                errors[provider] = error.localizedDescription
            }
        }

        snapshot = updated.providers.isEmpty ? nil : updated
        providerErrors = errors
        lastRefreshAt = Date()
    }

    private func startAutomaticRefresh() {
        Task { [weak self] in
            await self?.refresh()
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    private func result<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }
}
