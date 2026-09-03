import XCTest
@testable import Alerto

@MainActor
final class CodingAgentIntegrationStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var defaults: UserDefaults!
    private var store: CodingAgentIntegrationStore!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let suiteName = "CodingAgentIntegrationStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        store = CodingAgentIntegrationStore(
            homeDirectoryURL: temporaryDirectory,
            environment: ["PATH": ""],
            userDefaults: defaults
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testDetectedPiCanBeEnabledConfiguredAndDisabled() throws {
        let piRoot = temporaryDirectory.appendingPathComponent(".pi/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: piRoot, withIntermediateDirectories: true)
        store.refresh(port: 7531)

        XCTAssertEqual(store.snapshot(for: .pi, port: 7531).status, .available)

        store.setEnabled(true, for: .pi, port: 7531)
        var snapshot = store.snapshot(for: .pi, port: 7531)
        XCTAssertTrue(snapshot.isEnabled)
        XCTAssertEqual(snapshot.enabledEvents, [.completion])

        store.setEvent(.completion, enabled: false, for: .pi, port: 7531)
        snapshot = store.snapshot(for: .pi, port: 7531)
        XCTAssertFalse(snapshot.isEnabled)
        XCTAssertEqual(snapshot.status, .available)
    }

    func testPortUpdateRewritesEveryEnabledManagedIntegration() throws {
        let ompRoot = temporaryDirectory.appendingPathComponent(".omp/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: ompRoot, withIntermediateDirectories: true)
        store.refresh(port: 7531)
        store.setEnabled(true, for: .omp, port: 7531)

        store.updateInstalledIntegrations(port: 9000)

        let snapshot = store.snapshot(for: .omp, port: 9000)
        XCTAssertEqual(snapshot.status, .installed)
        let content = try String(contentsOf: XCTUnwrap(snapshot.integrationFile), encoding: .utf8)
        XCTAssertTrue(content.contains("// ALERTO_PORT=9000"))
        XCTAssertFalse(content.contains("// ALERTO_PORT=7531"))
    }

    func testManualPathOverrideTakesPrecedenceAndCanBeReset() throws {
        let customRoot = temporaryDirectory.appendingPathComponent("custom-pi", isDirectory: true)
        try FileManager.default.createDirectory(at: customRoot, withIntermediateDirectories: true)
        store.refresh(port: 7531)

        store.setPathOverride(customRoot, for: .pi, port: 7531)
        XCTAssertEqual(store.snapshot(for: .pi, port: 7531).resolvedDirectory, customRoot)
        XCTAssertTrue(store.hasPathOverride(for: .pi))

        store.resetPathOverride(for: .pi, port: 7531)
        XCTAssertEqual(
            store.snapshot(for: .pi, port: 7531).resolvedDirectory,
            temporaryDirectory.appendingPathComponent(".pi/agent", isDirectory: true)
        )
    }

    func testEnvironmentDirectoryIsResolvedBeforeDefault() throws {
        let customRoot = temporaryDirectory.appendingPathComponent("environment-pi", isDirectory: true)
        try FileManager.default.createDirectory(at: customRoot, withIntermediateDirectories: true)
        let environmentStore = CodingAgentIntegrationStore(
            homeDirectoryURL: temporaryDirectory,
            environment: ["PATH": "", "PI_CODING_AGENT_DIR": customRoot.path],
            userDefaults: defaults
        )

        environmentStore.refresh(port: 7531)

        XCTAssertEqual(environmentStore.snapshot(for: .pi, port: 7531).resolvedDirectory, customRoot)
        XCTAssertEqual(environmentStore.snapshot(for: .pi, port: 7531).status, .available)
    }

    func testUnavailableAgentRemainsVisibleButNotEnabled() {
        store.refresh(port: 7531)

        let snapshot = store.snapshot(for: .opencode, port: 7531)
        XCTAssertEqual(snapshot.status, .unavailable)
        XCTAssertFalse(snapshot.isDetected)
        XCTAssertFalse(snapshot.isEnabled)
    }
}
