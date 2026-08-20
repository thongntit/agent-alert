import Foundation
import LocalAuthentication
import Security

/// A read-only quota client based on the endpoints used by the Claude Code and Codex CLIs.
/// It never invokes a model, modifies credentials, or starts a coding session.
struct UsageClient {
    private let session: URLSession
    private let fileManager: FileManager

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    func fetchClaude(allowKeychainInteraction: Bool) async throws -> ProviderUsage {
        var credentials = try LocalCredentialReader(fileManager: fileManager)
            .claudeCredentials(allowKeychainInteraction: allowKeychainInteraction)

        do {
            return try await fetchClaude(credentials: credentials)
        } catch UsageFetchError.sessionExpired(.claude) {
            guard let refreshToken = credentials.refreshToken else {
                throw UsageFetchError.sessionExpired(.claude)
            }
            credentials = try await refreshClaude(credentials, refreshToken: refreshToken)
            return try await fetchClaude(credentials: credentials)
        }
    }

    private func fetchClaude(credentials: ClaudeLocalCredentials) async throws -> ProviderUsage {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 10
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.69", forHTTPHeaderField: "User-Agent")
        return try await execute(request, provider: .claude, mapper: UsageResponseMapper.claude)
    }

    private func refreshClaude(_ credentials: ClaudeLocalCredentials, refreshToken: String) async throws -> ClaudeLocalCredentials {
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            "scope": "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
        ])

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let refreshed = try? JSONDecoder().decode(ClaudeTokenResponse.self, from: data),
              !refreshed.accessToken.isEmpty else {
            throw UsageFetchError.sessionExpired(.claude)
        }

        var updated = credentials
        updated.accessToken = refreshed.accessToken
        updated.refreshToken = refreshed.refreshToken ?? credentials.refreshToken
        try LocalCredentialReader(fileManager: fileManager).saveClaude(updated)
        return updated
    }

    func fetchCodex() async throws -> ProviderUsage {
        var credentials = try LocalCredentialReader(fileManager: fileManager).codexCredentials()
        do {
            return try await fetchCodex(credentials: credentials)
        } catch UsageFetchError.sessionExpired(.codex) {
            guard let refreshToken = credentials.refreshToken else { throw UsageFetchError.sessionExpired(.codex) }
            credentials = try await refreshCodex(credentials, refreshToken: refreshToken)
            return try await fetchCodex(credentials: credentials)
        }
    }

    private func fetchCodex(credentials: CodexCredentials) async throws -> ProviderUsage {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.timeoutInterval = 10
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Alerto", forHTTPHeaderField: "User-Agent")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return try await execute(request, provider: .codex) { data in
            try UsageResponseMapper.codex(data: data)
        }
    }

    private func refreshCodex(_ credentials: CodexCredentials, refreshToken: String) async throws -> CodexCredentials {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=refresh_token&client_id=app_EMoamEEZ73f0CkXaXp7hrann&refresh_token=\(refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken)"
        request.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              let refreshed = try? JSONDecoder().decode(CodexTokenResponse.self, from: data),
              !refreshed.accessToken.isEmpty else {
            throw UsageFetchError.sessionExpired(.codex)
        }

        var updated = credentials
        updated.accessToken = refreshed.accessToken
        updated.refreshToken = refreshed.refreshToken ?? credentials.refreshToken
        updated.idToken = refreshed.idToken ?? credentials.idToken
        try LocalCredentialReader(fileManager: fileManager).saveCodex(updated)
        return updated
    }

    private func execute(
        _ request: URLRequest,
        provider: UsageProvider,
        mapper: (Data) throws -> ProviderUsage
    ) async throws -> ProviderUsage {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw UsageFetchError.invalidResponse(provider)
            }
            if response.statusCode == 401 || response.statusCode == 403 {
                throw UsageFetchError.sessionExpired(provider)
            }
            guard (200..<300).contains(response.statusCode) else {
                throw UsageFetchError.requestFailed(provider, response.statusCode)
            }
            return try mapper(data)
        } catch let error as UsageFetchError {
            throw error
        } catch is URLError {
            throw UsageFetchError.connectionFailed(provider)
        } catch {
            throw UsageFetchError.invalidResponse(provider)
        }
    }
}

private struct LocalCredentialReader {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func claudeCredentials(allowKeychainInteraction: Bool) throws -> ClaudeLocalCredentials {
        // Automatic refreshes may read an already-authorized Keychain item without UI. A manual
        // refresh uses the same lookup with interaction enabled, allowing macOS to offer Always Allow.
        let keychainResult = claudeKeychainCredentials(allowInteraction: allowKeychainInteraction)
        if case .success(let credentials) = keychainResult,
           let accessToken = credentials.accessToken,
           !accessToken.isEmpty {
            return ClaudeLocalCredentials(accessToken: accessToken, refreshToken: credentials.refreshToken, path: nil)
        }

        let configurationHome = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
        let path = URL(fileURLWithPath: configurationHome).appendingPathComponent(".credentials.json")
        guard let data = try? Data(contentsOf: path),
              let credentials = try? JSONDecoder().decode(ClaudeCredentials.self, from: data),
               let oauth = credentials.claudeAiOauth,
               let accessToken = oauth.accessToken,
               !accessToken.isEmpty
        else {
            if case .failure(let error) = keychainResult, allowKeychainInteraction {
                throw error
            }
            throw UsageFetchError.notSignedIn(.claude)
        }
        return ClaudeLocalCredentials(
            accessToken: accessToken,
            refreshToken: oauth.refreshToken,
            path: path
        )
    }

    func saveClaude(_ credentials: ClaudeLocalCredentials) throws {
        guard let path = credentials.path else { return }
        let oauth = ClaudeOAuth(accessToken: credentials.accessToken, refreshToken: credentials.refreshToken)
        try JSONEncoder().encode(ClaudeCredentials(claudeAiOauth: oauth)).write(to: path, options: .atomic)
    }

    func codexCredentials() throws -> CodexCredentials {
        let environment = ProcessInfo.processInfo.environment
        let homes: [URL]
        if let configuredHome = environment["CODEX_HOME"], !configuredHome.isEmpty {
            homes = [URL(fileURLWithPath: configuredHome)]
        } else {
            let home = fileManager.homeDirectoryForCurrentUser
            homes = [
                home.appendingPathComponent(".codex"),
                home.appendingPathComponent(".config/codex")
            ]
        }

        for home in homes {
            let path = home.appendingPathComponent("auth.json")
            guard let data = try? Data(contentsOf: path),
                  let credentials = try? JSONDecoder().decode(CodexAuthFile.self, from: data),
                  let accessToken = credentials.tokens?.accessToken,
                  !accessToken.isEmpty
            else {
                continue
            }
            return CodexCredentials(accessToken: accessToken, refreshToken: credentials.tokens?.refreshToken, idToken: credentials.tokens?.idToken, accountID: credentials.tokens?.accountID, source: .file(path))
        }

        if let data = keychainData(service: "Codex Auth"),
           let credentials = try? JSONDecoder().decode(CodexAuthFile.self, from: data),
           let accessToken = credentials.tokens?.accessToken,
           !accessToken.isEmpty {
            return CodexCredentials(accessToken: accessToken, refreshToken: credentials.tokens?.refreshToken, idToken: credentials.tokens?.idToken, accountID: credentials.tokens?.accountID, source: .keychain)
        }
        throw UsageFetchError.notSignedIn(.codex)
    }

    func saveCodex(_ credentials: CodexCredentials) throws {
        let tokens = CodexTokens(accessToken: credentials.accessToken, refreshToken: credentials.refreshToken, idToken: credentials.idToken, accountID: credentials.accountID)
        let data = try JSONEncoder().encode(CodexAuthFile(tokens: tokens))
        switch credentials.source {
        case .file(let path): try data.write(to: path, options: .atomic)
        case .keychain:
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Codex Auth"]
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard status == errSecSuccess else { throw UsageFetchError.sessionExpired(.codex) }
        }
    }

    private func keychainData(service: String) -> Data? {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func claudeKeychainCredentials(allowInteraction: Bool) -> Result<ClaudeOAuth, UsageFetchError> {
        for includeAccount in [true, false] {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "Claude Code-credentials",
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            if includeAccount {
                query[kSecAttrAccount as String] = NSUserName()
            }
            if !allowInteraction {
                // Automatic refreshes must not show authentication UI. Manual refreshes omit this
                // context so macOS can present its normal Keychain prompt and Always Allow choice.
                let context = LAContext()
                context.interactionNotAllowed = true
                query[kSecUseAuthenticationContext as String] = context
            }

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            switch status {
            case errSecSuccess:
                guard let data = item as? Data,
                      let credentials = try? JSONDecoder().decode(ClaudeCredentials.self, from: data),
                      let oauth = credentials.claudeAiOauth
                else {
                    continue
                }
                return .success(oauth)
            case errSecItemNotFound:
                continue
            case errSecInteractionNotAllowed, errSecAuthFailed:
                return .failure(.keychainAccessRequired)
            default:
                continue
            }
        }
        return .failure(.notSignedIn(.claude))
    }
}

private struct ClaudeCredentials: Codable {
    let claudeAiOauth: ClaudeOAuth?
}

private struct ClaudeOAuth: Codable {
    let accessToken: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
    }
}

private struct ClaudeLocalCredentials {
    var accessToken: String
    var refreshToken: String?
    let path: URL?
}

private struct ClaudeTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct CodexCredentials {
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    let accountID: String?
    let source: Source

    enum Source {
        case file(URL)
        case keychain
    }
}

private struct CodexAuthFile: Codable {
    let tokens: CodexTokens?

    init(tokens: CodexTokens?) { self.tokens = tokens }
}

private struct CodexTokens: Codable {
    let accessToken: String?
    let refreshToken: String?
    let idToken: String?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case accountID = "account_id"
    }
}

private struct CodexTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }
}
