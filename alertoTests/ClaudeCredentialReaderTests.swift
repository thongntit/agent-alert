import XCTest
@testable import Alerto

final class ClaudeCredentialReaderTests: XCTestCase {
    private var configurationDirectory: URL!

    override func setUpWithError() throws {
        configurationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlertoClaudeCredentialReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: configurationDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let configurationDirectory {
            try? FileManager.default.removeItem(at: configurationDirectory)
        }
        configurationDirectory = nil
    }

    func testReadsCredentialFileFromClaudeConfigDirectory() throws {
        try writeCredentialFile(accessToken: "file-token", refreshToken: "file-refresh")

        let credentials = try makeReader().claudeCredentials()

        XCTAssertEqual(credentials.accessToken, "file-token")
        XCTAssertEqual(credentials.refreshToken, "file-refresh")
        XCTAssertEqual(
            credentials.path,
            configurationDirectory.appendingPathComponent(".credentials.json")
        )
    }

    func testReadingCredentialCacheDoesNotQueryKeychain() throws {
        try writeCredentialFile(accessToken: "file-token", refreshToken: "file-refresh")
        var queriedKeychain = false
        let reader = LocalCredentialReader(
            fileManager: .default,
            environment: ["CLAUDE_CONFIG_DIR": configurationDirectory.path],
            keychainDataProvider: { _, _ in
                queriedKeychain = true
                return nil
            }
        )

        _ = try reader.claudeCredentials()

        XCTAssertFalse(queriedKeychain)
    }

    func testMissingCredentialFileReportsClaudeNotSignedIn() {
        XCTAssertThrowsError(try makeReader().claudeCredentials()) { error in
            XCTAssertEqual(error as? UsageFetchError, .notSignedIn(.claude))
        }
    }

    func testCredentialFileWithoutAccessTokenReportsInvalidToken() throws {
        try writeCredentialFile(accessToken: nil, refreshToken: "file-refresh")

        XCTAssertThrowsError(try makeReader().claudeCredentials()) { error in
            XCTAssertEqual(error as? UsageFetchError, .invalidToken(.claude))
        }
    }

    func testSavingRefreshedCredentialPreservesOAuthMetadata() throws {
        let path = configurationDirectory.appendingPathComponent(".credentials.json")
        let original: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": "old-token",
                "refreshToken": "old-refresh",
                "expiresAt": 1_750_000_000_000,
                "scopes": ["user:inference"],
                "subscriptionType": "team"
            ]
        ]
        try JSONSerialization.data(withJSONObject: original).write(to: path, options: .atomic)

        try makeReader().saveClaude(
            ClaudeLocalCredentials(
                accessToken: "new-token",
                refreshToken: "new-refresh",
                path: path
            )
        )

        let savedData = try Data(contentsOf: path)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: savedData) as? [String: Any])
        let oauth = try XCTUnwrap(saved["claudeAiOauth"] as? [String: Any])
        XCTAssertEqual(oauth["accessToken"] as? String, "new-token")
        XCTAssertEqual(oauth["refreshToken"] as? String, "new-refresh")
        XCTAssertEqual(oauth["expiresAt"] as? Int, 1_750_000_000_000)
        XCTAssertEqual(oauth["scopes"] as? [String], ["user:inference"])
        XCTAssertEqual(oauth["subscriptionType"] as? String, "team")
    }

    func testSavingRefreshedCredentialPreservesOwnerOnlyFilePermissions() throws {
        try writeCredentialFile(accessToken: "old-token", refreshToken: "old-refresh")
        let path = configurationDirectory.appendingPathComponent(".credentials.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        let credentials = ClaudeLocalCredentials(
            accessToken: "new-token",
            refreshToken: "new-refresh",
            path: path
        )

        try makeReader().saveClaude(credentials)

        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        let saved = try makeReader().claudeCredentials()
        XCTAssertEqual(saved.accessToken, "new-token")
        XCTAssertEqual(saved.refreshToken, "new-refresh")
    }

    func testImportsKeychainCredentialIntoCacheWithoutChangingDocument() throws {
        let original: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": "keychain-token",
                "refreshToken": "keychain-refresh",
                "expiresAt": 1_750_000_000_000,
                "refreshTokenExpiresAt": 1_760_000_000_000,
                "scopes": ["user:inference"],
                "subscriptionType": "team"
            ],
            "otherMetadata": "preserved"
        ]
        let keychainData = try JSONSerialization.data(withJSONObject: original, options: [.sortedKeys])
        var requestedService: String?
        var requestedPrompt = false
        let reader = LocalCredentialReader(
            fileManager: .default,
            environment: ["CLAUDE_CONFIG_DIR": configurationDirectory.path],
            keychainDataProvider: { service, allowPrompt in
                requestedService = service
                requestedPrompt = allowPrompt
                return keychainData
            }
        )

        let credentials = try reader.importClaudeFromKeychain()

        XCTAssertEqual(requestedService, "Claude Code-credentials")
        XCTAssertTrue(requestedPrompt)
        XCTAssertEqual(credentials.accessToken, "keychain-token")
        XCTAssertEqual(credentials.refreshToken, "keychain-refresh")

        let cachePath = configurationDirectory.appendingPathComponent(".credentials.json")
        XCTAssertEqual(try Data(contentsOf: cachePath), keychainData)
        let attributes = try FileManager.default.attributesOfItem(atPath: cachePath.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    private func makeReader() -> LocalCredentialReader {
        LocalCredentialReader(
            fileManager: .default,
            environment: ["CLAUDE_CONFIG_DIR": configurationDirectory.path]
        )
    }

    private func writeCredentialFile(accessToken: String?, refreshToken: String?) throws {
        let credentials = ClaudeCredentials(
            claudeAiOauth: ClaudeOAuth(
                accessToken: accessToken,
                refreshToken: refreshToken
            )
        )
        let data = try JSONEncoder().encode(credentials)
        try data.write(
            to: configurationDirectory.appendingPathComponent(".credentials.json"),
            options: .atomic
        )
    }
}
