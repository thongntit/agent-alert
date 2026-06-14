import XCTest
@testable import Alerto

@MainActor
final class CodexHookManagerTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var codexHome: URL!
    private var manager: CodexHookManager!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        codexHome = temporaryDirectory.appendingPathComponent(".codex", isDirectory: true)
        manager = CodexHookManager(codexHomeURL: codexHome)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testInstallAllCreatesSeparateCodexMatcherGroups() throws {
        try manager.installHooks(port: 7531)

        let root = try loadRoot()
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual(hooks.count, 3)

        for hook in CodexHookManager.HookName.allCases {
            let groups = try XCTUnwrap(hooks[hook.eventName] as? [[String: Any]])
            XCTAssertEqual(groups.count, 1)
            let handlers = try XCTUnwrap(groups[0]["hooks"] as? [[String: Any]])
            XCTAssertEqual(handlers.count, 1)
            let command = try XCTUnwrap(handlers[0]["command"] as? String)
            XCTAssertTrue(command.contains(hook.marker))
            XCTAssertTrue(command.contains("source=codex&type=\(hook.notificationType)"))
            XCTAssertTrue(command.contains("printf '{}'"))
        }
    }

    func testReinstallIsIdempotentAndUpdatesPort() throws {
        try manager.installHooks(port: 7531)
        try manager.installHooks(port: 9123)

        let commands = try allCommands()
        XCTAssertEqual(commands.count, 3)
        XCTAssertTrue(commands.allSatisfy { $0.contains(":9123/notify") })
        XCTAssertFalse(commands.contains { $0.contains(":7531/notify") })
    }

    func testInstallPreservesUnknownFieldsAndUnrelatedHooks() throws {
        try writeRoot([
            "version": 7,
            "custom": ["enabled": true],
            "hooks": [
                "Stop": [[
                    "matcher": "existing",
                    "customGroupField": "keep",
                    "hooks": [[
                        "type": "command",
                        "command": "echo existing",
                        "customHandlerField": 42
                    ]]
                ]],
                "FutureEvent": [[
                    "hooks": [["type": "command", "command": "echo future"]]
                ]]
            ]
        ])

        try manager.installHook(name: "stop", port: 7531)
        let installed = try loadRoot()
        XCTAssertEqual(installed["version"] as? Int, 7)
        XCTAssertNotNil(installed["custom"])
        XCTAssertTrue(try allCommands().contains("echo existing"))
        XCTAssertTrue(try allCommands().contains("echo future"))

        try manager.uninstallHook(name: "stop")
        let removed = try loadRoot()
        XCTAssertEqual(removed["version"] as? Int, 7)
        XCTAssertTrue(try allCommands().contains("echo existing"))
        XCTAssertTrue(try allCommands().contains("echo future"))
        XCTAssertFalse(manager.isAnyHookInstalled())
    }

    func testBulkRemovalOnlyRemovesAlertoHandlers() throws {
        try manager.installHooks(port: 7531)
        var root = try loadRoot()
        var hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        hooks["Stop"] = (hooks["Stop"] as? [Any] ?? []) + [[
            "hooks": [["type": "command", "command": "echo user-hook"]]
        ]]
        root["hooks"] = hooks
        try writeRoot(root)

        try manager.uninstallHooks()

        XCTAssertEqual(try allCommands(), ["echo user-hook"])
        XCTAssertFalse(manager.isAnyHookInstalled())
    }

    func testMalformedConfigurationIsNotOverwritten() throws {
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let malformed = Data(#"{"hooks":{"Stop":"invalid"}}"#.utf8)
        try malformed.write(to: manager.hooksPath)

        XCTAssertThrowsError(try manager.installHooks(port: 7531))
        XCTAssertEqual(try Data(contentsOf: manager.hooksPath), malformed)
    }

    private func loadRoot() throws -> [String: Any] {
        let data = try Data(contentsOf: manager.hooksPath)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func writeRoot(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: manager.hooksPath)
    }

    private func allCommands() throws -> [String] {
        let root = try loadRoot()
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        return hooks.values.flatMap { rawGroups -> [String] in
            guard let groups = rawGroups as? [[String: Any]] else { return [] }
            return groups.flatMap { group -> [String] in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return [] }
                return handlers.compactMap { $0["command"] as? String }
            }
        }
    }
}
