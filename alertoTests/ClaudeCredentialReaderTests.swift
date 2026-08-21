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

    func testMissingCredentialFileReportsClaudeNotSignedIn() {
        XCTAssertThrowsError(try makeReader().claudeCredentials()) { error in
            XCTAssertEqual(error as? UsageFetchError, .notSignedIn(.claude))
        }
    }

    func testCredentialFileWithoutAccessTokenReportsClaudeNotSignedIn() throws {
        try writeCredentialFile(accessToken: nil, refreshToken: "file-refresh")

        XCTAssertThrowsError(try makeReader().claudeCredentials()) { error in
            XCTAssertEqual(error as? UsageFetchError, .notSignedIn(.claude))
        }
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
