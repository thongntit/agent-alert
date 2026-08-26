import XCTest
@testable import Alerto

final class ClaudeCodeHookManagerTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var manager: ClaudeCodeHookManager!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        manager = ClaudeCodeHookManager(claudeConfigURL: temporaryDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testBulkRemovalUsesDurableCommandSignatureAndPreservesUnrelatedHooks() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let settings: [String: Any] = [
            "custom": ["keep": true],
            "hooks": [
                "Stop": [
                    ["hooks": [[
                        "type": "command",
                        "command": "curl http://127.0.0.1:7531/notify"
                    ]]],
                    ["hooks": [[
                        "type": "command",
                        "command": "echo keep-me"
                    ]]]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted])
        try data.write(to: manager.settingsPath)

        XCTAssertTrue(manager.isAnyHookInstalled())
        try manager.uninstallHooks()

        let updatedData = try Data(contentsOf: manager.settingsPath)
        let updated = try XCTUnwrap(JSONSerialization.jsonObject(with: updatedData) as? [String: Any])
        XCTAssertNotNil(updated["custom"])
        let hooks = try XCTUnwrap(updated["hooks"] as? [String: [[String: Any]]])
        let stop = try XCTUnwrap(hooks["Stop"])
        let commands = stop.flatMap { entry in
            (entry["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
        XCTAssertEqual(commands, ["echo keep-me"])
        XCTAssertFalse(manager.isAnyHookInstalled())
    }
}
