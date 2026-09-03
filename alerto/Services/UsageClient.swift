import Foundation
import LocalAuthentication
import Security

/// A read-only quota client based on the endpoints used by the Claude Code and Codex CLIs.
/// It never invokes a model or starts a coding session. Claude credentials are read from
/// Alerto's local cache; a manual refresh can bootstrap that cache from Claude Code's Keychain.
struct UsageClient {
    private let session: URLSession
    private let fileManager: FileManager
    private let environment: [String: String]
    private let keychainDataProvider: ((String, Bool) -> Data?)?

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        keychainDataProvider: ((String, Bool) -> Data?)? = nil
    ) {
        self.session = session
        self.fileManager = fileManager
        self.environment = environment
        self.keychainDataProvider = keychainDataProvider
    }

    func fetchClaude(allowKeychainBootstrap: Bool = false) async throws -> ProviderUsage {
        let reader = LocalCredentialReader(
            fileManager: fileManager,
            environment: environment,
            keychainDataProvider: keychainDataProvider
        )
        var importedFromKeychain = false
        var credentials: ClaudeLocalCredentials

        do {
            credentials = try reader.claudeCredentials()
        } catch let error as UsageFetchError {
            guard allowKeychainBootstrap else { throw error }
            switch error {
            case .notSignedIn(.claude), .invalidToken(.claude):
                credentials = try reader.importClaudeFromKeychain()
                importedFromKeychain = true
            default:
                throw error
            }
        }

        do {
            return try await fetchClaude(credentials: credentials)
        } catch UsageFetchError.invalidToken(.claude) {
            if let refreshToken = credentials.refreshToken {
                do {
                    credentials = try await refreshClaude(credentials, refreshToken: refreshToken)
                    return try await fetchClaude(credentials: credentials)
                } catch UsageFetchError.invalidToken(.claude) {
                    // The refresh token can be stale while Claude Code's Keychain
                    // still has a current login. Fall through to a manual import.
                }
            }

            guard allowKeychainBootstrap, !importedFromKeychain else {
                throw UsageFetchError.invalidToken(.claude)
            }
            credentials = try reader.importClaudeFromKeychain()
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
        guard let response = response as? HTTPURLResponse else {
            throw UsageFetchError.invalidResponse(.claude)
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw UsageFetchError.invalidToken(.claude)
        }
        if response.statusCode == 429 {
            throw UsageFetchError.rateLimited(.claude)
        }
        if response.statusCode == 400,
           Self.isInvalidClaudeOAuthCredentialResponse(data) {
            throw UsageFetchError.invalidToken(.claude)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw UsageFetchError.requestFailed(.claude, response.statusCode)
        }
        guard let refreshed = try? JSONDecoder().decode(ClaudeTokenResponse.self, from: data),
              !refreshed.accessToken.isEmpty else {
            throw UsageFetchError.invalidResponse(.claude)
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
        } catch UsageFetchError.invalidToken(.codex) {
            guard let refreshToken = credentials.refreshToken else { throw UsageFetchError.invalidToken(.codex) }
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
        guard let response = response as? HTTPURLResponse else {
            throw UsageFetchError.invalidResponse(.codex)
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw UsageFetchError.invalidToken(.codex)
        }
        if response.statusCode == 429 {
            throw UsageFetchError.rateLimited(.codex)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw UsageFetchError.requestFailed(.codex, response.statusCode)
        }
        guard let refreshed = try? JSONDecoder().decode(CodexTokenResponse.self, from: data),
              !refreshed.accessToken.isEmpty else {
            throw UsageFetchError.invalidResponse(.codex)
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
                throw UsageFetchError.invalidToken(provider)
            }
            if response.statusCode == 429 {
                throw UsageFetchError.rateLimited(provider)
            }
            if response.statusCode == 400,
               provider == .claude,
               Self.isInvalidClaudeOAuthCredentialResponse(data) {
                throw UsageFetchError.invalidToken(provider)
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

    private static func isInvalidClaudeOAuthCredentialResponse(_ data: Data) -> Bool {
        guard let body = String(data: data, encoding: .utf8)?.lowercased() else {
            return false
        }

        if body.contains("invalid_grant") {
            return true
        }

        return body.contains("token") && (
            body.contains("revoked") ||
            body.contains("expired") ||
            body.contains("invalid")
        )
    }
}

struct LocalCredentialReader {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let keychainDataProvider: (String, Bool) -> Data?

    init(
        fileManager: FileManager,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        keychainDataProvider: ((String, Bool) -> Data?)? = nil
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.keychainDataProvider = keychainDataProvider ?? { service, allowPrompt in
            LocalCredentialReader.readKeychainData(service: service, allowPrompt: allowPrompt)
        }
    }

    func claudeCredentials() throws -> ClaudeLocalCredentials {
        let path = claudeCredentialsPath()
        if let credentials = readClaudeCredentials(at: path) {
            return credentials
        }

        let fileError: UsageFetchError = fileManager.fileExists(atPath: path.path)
            ? .invalidToken(.claude)
            : .notSignedIn(.claude)
        throw fileError
    }

    /// Imports Claude Code's macOS Keychain credential once and caches the exact
    /// credential document in the file Alerto uses for subsequent refreshes.
    func importClaudeFromKeychain() throws -> ClaudeLocalCredentials {
        let path = claudeCredentialsPath()
        guard let data = keychainDataProvider("Claude Code-credentials", true),
              let credentials = decodeClaudeCredentials(data: data, path: path) else {
            throw UsageFetchError.invalidToken(.claude)
        }

        try saveClaudeDocument(data, to: path)
        return credentials
    }

    func saveClaude(_ credentials: ClaudeLocalCredentials) throws {
        var document: [String: Any]
        if let data = try? Data(contentsOf: credentials.path),
           let object = try? JSONSerialization.jsonObject(with: data),
           let existing = object as? [String: Any] {
            document = existing
        } else {
            document = [:]
        }

        var oauth = document["claudeAiOauth"] as? [String: Any] ?? [:]
        oauth["accessToken"] = credentials.accessToken
        if let refreshToken = credentials.refreshToken {
            oauth["refreshToken"] = refreshToken
        } else {
            oauth.removeValue(forKey: "refreshToken")
        }
        document["claudeAiOauth"] = oauth

        let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        try saveClaudeDocument(data, to: credentials.path)
    }

    private func claudeCredentialsPath() -> URL {
        let configurationHome = environment["CLAUDE_CONFIG_DIR"].flatMap { value in
            value.isEmpty ? nil : value
        } ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
        return URL(fileURLWithPath: configurationHome).appendingPathComponent(".credentials.json")
    }

    private func readClaudeCredentials(at path: URL) -> ClaudeLocalCredentials? {
        guard let data = try? Data(contentsOf: path) else { return nil }
        return decodeClaudeCredentials(data: data, path: path)
    }

    private func decodeClaudeCredentials(data: Data, path: URL) -> ClaudeLocalCredentials? {
        guard let credentials = try? JSONDecoder().decode(ClaudeCredentials.self, from: data),
              let oauth = credentials.claudeAiOauth,
              let accessToken = oauth.accessToken,
              !accessToken.isEmpty else {
            return nil
        }
        return ClaudeLocalCredentials(
            accessToken: accessToken,
            refreshToken: oauth.refreshToken,
            path: path
        )
    }

    private func saveClaudeDocument(_ data: Data, to path: URL) throws {
        try fileManager.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: path, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path.path
        )
    }

    fileprivate func codexCredentials() throws -> CodexCredentials {
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

        if let data = keychainDataProvider("Codex Auth", false),
           let credentials = try? JSONDecoder().decode(CodexAuthFile.self, from: data),
           let accessToken = credentials.tokens?.accessToken,
           !accessToken.isEmpty {
            return CodexCredentials(accessToken: accessToken, refreshToken: credentials.tokens?.refreshToken, idToken: credentials.tokens?.idToken, accountID: credentials.tokens?.accountID, source: .keychain)
        }
        throw UsageFetchError.notSignedIn(.codex)
    }

    fileprivate func saveCodex(_ credentials: CodexCredentials) throws {
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

    private static func readKeychainData(service: String, allowPrompt: Bool) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !allowPrompt {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

}

struct ClaudeCredentials: Codable {
    let claudeAiOauth: ClaudeOAuth?
}

struct ClaudeOAuth: Codable {
    let accessToken: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
    }
}

struct ClaudeLocalCredentials {
    var accessToken: String
    var refreshToken: String?
    let path: URL
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
