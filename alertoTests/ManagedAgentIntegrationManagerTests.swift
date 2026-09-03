import XCTest
@testable import Alerto

final class ManagedAgentIntegrationManagerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testPiInstallWritesOwnedVersionedExtensionAndUpdatesPort() throws {
        let manager = ManagedAgentIntegrationManager(agent: .pi, rootDirectory: temporaryDirectory)

        try manager.install(events: [.completion], port: 7531)

        XCTAssertTrue(manager.isOwnedFile())
        XCTAssertEqual(manager.installedEvents(), [.completion])
        XCTAssertEqual(manager.status(currentPort: 7531, isDetected: true), .installed)
        XCTAssertEqual(manager.status(currentPort: 9123, isDetected: true), .updateRequired)

        try manager.install(events: [.completion], port: 9123)
        let content = try String(contentsOf: XCTUnwrap(manager.integrationFile), encoding: .utf8)
        XCTAssertTrue(content.contains("// ALERTO_INTEGRATION_ID=pi"))
        XCTAssertTrue(content.contains("// ALERTO_INTEGRATION_VERSION=1"))
        XCTAssertTrue(content.contains("// ALERTO_PORT=9123"))
        XCTAssertTrue(content.contains("pi.on(\"agent_settled\""))
        XCTAssertFalse(content.contains("7531"))
    }

    func testOmpTemplateIncludesAttentionRetryAndIdleHandling() throws {
        let manager = ManagedAgentIntegrationManager(agent: .omp, rootDirectory: temporaryDirectory)
        try manager.install(events: [.completion, .permission, .question, .error], port: 7531)

        let content = try String(contentsOf: XCTUnwrap(manager.integrationFile), encoding: .utf8)
        XCTAssertTrue(content.contains("tool_approval_requested"))
        XCTAssertTrue(content.contains("event?.toolName !== \"ask\""))
        XCTAssertTrue(content.contains("retryableErrorPattern"))
        XCTAssertTrue(content.contains("}, 2500)"))
        XCTAssertTrue(content.contains("}, 250)"))
    }

    func testOpenCodeTemplateSeparatesChildSessionsAndDeduplicatesIdle() throws {
        let manager = ManagedAgentIntegrationManager(agent: .opencode, rootDirectory: temporaryDirectory)
        try manager.install(events: [.completion, .permission, .question, .error], port: 7531)

        let content = try String(contentsOf: XCTUnwrap(manager.integrationFile), encoding: .utf8)
        XCTAssertTrue(content.contains("const childSessions = new Set()"))
        XCTAssertTrue(content.contains("completionArmed"))
        XCTAssertTrue(content.contains("completionSent"))
        XCTAssertTrue(content.contains("case \"session.status\""))
        XCTAssertTrue(content.contains("case \"session.idle\""))
        XCTAssertTrue(content.contains("case \"permission.asked\""))
        XCTAssertTrue(content.contains("case \"question.asked\""))
    }

    func testInstallRefusesToOverwriteForeignFile() throws {
        let manager = ManagedAgentIntegrationManager(agent: .opencode, rootDirectory: temporaryDirectory)
        let file = try XCTUnwrap(manager.integrationFile)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("export const UserPlugin = async () => ({});".utf8)
        try original.write(to: file)

        XCTAssertThrowsError(try manager.install(events: [.completion], port: 7531))
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(manager.status(currentPort: 7531, isDetected: true), .conflict)
    }

    func testUninstallRemovesOnlyOwnedFile() throws {
        let manager = ManagedAgentIntegrationManager(agent: .pi, rootDirectory: temporaryDirectory)
        try manager.install(events: [.completion], port: 7531)
        let file = try XCTUnwrap(manager.integrationFile)

        try manager.uninstall()

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
    }
}
