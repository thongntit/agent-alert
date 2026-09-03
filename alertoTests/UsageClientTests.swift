import Foundation
import XCTest
@testable import Alerto

final class UsageClientTests: XCTestCase {
    private var configurationDirectory: URL!

    override func setUpWithError() throws {
        configurationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlertoUsageClientTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: configurationDirectory,
            withIntermediateDirectories: true
        )
        MockURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        MockURLProtocol.reset()
        if let configurationDirectory {
            try? FileManager.default.removeItem(at: configurationDirectory)
        }
        configurationDirectory = nil
    }

    func testManualRefreshImportsKeychainWhenRefreshTokenIsRevoked() async throws {
        try writeCredentialFile(accessToken: "revoked-access", refreshToken: "revoked-refresh")

        let keychainData = Data(#"""
        {
          "claudeAiOauth": {
            "accessToken": "keychain-access",
            "refreshToken": "keychain-refresh",
            "subscriptionType": "team"
          }
        }
        """#.utf8)
        let calls = KeychainCallRecorder()
        MockURLProtocol.enqueue([
            .init(statusCode: 401, body: #"{"error":{"message":"OAuth access token has been revoked."}}"#),
            .init(statusCode: 400, body: #"{"error":"invalid_grant","error_description":"Refresh token has been revoked."}"#),
            .init(statusCode: 200, body: #"{"five_hour":{"utilization":5},"seven_day":{"utilization":1}}"#)
        ])

        let client = makeClient { service, allowPrompt in
            calls.record(service: service, allowPrompt: allowPrompt)
            return keychainData
        }

        let usage = try await client.fetchClaude(allowKeychainBootstrap: true)

        XCTAssertEqual(usage.limits.map(\.formattedRemaining), ["95% left", "99% left"])
        XCTAssertEqual(calls.services, ["Claude Code-credentials"])
        XCTAssertEqual(calls.promptFlags, [true])
        XCTAssertEqual(MockURLProtocol.requests.count, 3)
        XCTAssertEqual(
            MockURLProtocol.requests.map { $0.url?.absoluteString },
            [
                "https://api.anthropic.com/api/oauth/usage",
                "https://platform.claude.com/v1/oauth/token",
                "https://api.anthropic.com/api/oauth/usage"
            ]
        )

        let savedData = try Data(
            contentsOf: configurationDirectory.appendingPathComponent(".credentials.json")
        )
        XCTAssertEqual(savedData, keychainData)
    }

    func testManualRefreshImportsKeychainWhenUsageResponseReportsRevokedTokenWith400() async throws {
        try writeCredentialFile(accessToken: "revoked-access", refreshToken: nil)

        let keychainData = Data(#"{"claudeAiOauth":{"accessToken":"keychain-access"}}"#.utf8)
        let calls = KeychainCallRecorder()
        MockURLProtocol.enqueue([
            .init(statusCode: 400, body: #"{"type":"error","error":{"type":"authentication_error","message":"OAuth access token has been revoked."}}"#),
            .init(statusCode: 200, body: #"{"five_hour":{"utilization":10}}"#)
        ])

        let client = makeClient { service, allowPrompt in
            calls.record(service: service, allowPrompt: allowPrompt)
            return keychainData
        }

        let usage = try await client.fetchClaude(allowKeychainBootstrap: true)

        XCTAssertEqual(usage.limits.map(\.formattedRemaining), ["90% left"])
        XCTAssertEqual(calls.services, ["Claude Code-credentials"])
        XCTAssertEqual(calls.promptFlags, [true])
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
    }

    func testNonAuthentication400DoesNotPromptKeychain() async throws {
        try writeCredentialFile(accessToken: "file-access", refreshToken: nil)

        let calls = KeychainCallRecorder()
        MockURLProtocol.enqueue([
            .init(statusCode: 400, body: #"{"type":"error","error":{"type":"invalid_request_error","message":"Malformed request."}}"#)
        ])

        let client = makeClient { service, allowPrompt in
            calls.record(service: service, allowPrompt: allowPrompt)
            return nil
        }

        do {
            _ = try await client.fetchClaude(allowKeychainBootstrap: true)
            XCTFail("Expected the non-authentication 400 response to fail")
        } catch let error as UsageFetchError {
            XCTAssertEqual(error, .requestFailed(.claude, 400))
        }

        XCTAssertTrue(calls.services.isEmpty)
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    func testAutomaticRefreshDoesNotPromptKeychainForRevokedToken() async throws {
        try writeCredentialFile(accessToken: "revoked-access", refreshToken: nil)

        let calls = KeychainCallRecorder()
        MockURLProtocol.enqueue([
            .init(statusCode: 400, body: #"{"error":{"message":"OAuth access token has been revoked."}}"#)
        ])

        let client = makeClient { service, allowPrompt in
            calls.record(service: service, allowPrompt: allowPrompt)
            return nil
        }

        do {
            _ = try await client.fetchClaude()
            XCTFail("Expected the automatic refresh to fail without Keychain access")
        } catch let error as UsageFetchError {
            XCTAssertEqual(error, .invalidToken(.claude))
        }

        XCTAssertTrue(calls.services.isEmpty)
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    private func makeClient(
        keychainDataProvider: @escaping (String, Bool) -> Data?
    ) -> UsageClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return UsageClient(
            session: URLSession(configuration: configuration),
            fileManager: .default,
            environment: ["CLAUDE_CONFIG_DIR": configurationDirectory.path],
            keychainDataProvider: keychainDataProvider
        )
    }

    private func writeCredentialFile(accessToken: String, refreshToken: String?) throws {
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

private final class KeychainCallRecorder {
    private(set) var services: [String] = []
    private(set) var promptFlags: [Bool] = []

    func record(service: String, allowPrompt: Bool) {
        services.append(service)
        promptFlags.append(allowPrompt)
    }
}

private final class MockURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let body: Data

        init(statusCode: Int, body: String) {
            self.statusCode = statusCode
            self.body = Data(body.utf8)
        }
    }

    private static let lock = NSLock()
    private static var stubs: [Stub] = []
    private(set) static var requests: [URLRequest] = []

    static func enqueue(_ stubs: [Stub]) {
        lock.lock()
        self.stubs = stubs
        requests = []
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        stubs = []
        requests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let stub: Stub?
        Self.lock.lock()
        if Self.stubs.isEmpty {
            stub = nil
        } else {
            stub = Self.stubs.removeFirst()
            Self.requests.append(request)
        }
        Self.lock.unlock()

        guard let stub,
              let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: stub.statusCode,
                  httpVersion: nil,
                  headerFields: nil
              ) else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.resourceUnavailable)
            )
            return
        }

        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
