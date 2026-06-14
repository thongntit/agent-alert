import XCTest
@testable import Alerto

final class HookPayloadTests: XCTestCase {
    func testCodexStopPayloadMapping() throws {
        let payload = try decode(#"{"hook_event_name":"Stop","last_assistant_message":"Implemented the change."}"#)
        XCTAssertEqual(payload.effectiveMessage, "Implemented the change.")
        XCTAssertEqual(payload.effectiveType, "complete")
        XCTAssertEqual(payload.effectiveHookType, .stop)
    }

    func testCodexPermissionRequestUsesDescriptionThenToolFallback() throws {
        let described = try decode(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash","last_assistant_message":"Older context","tool_input":{"description":"Run the release command"}}"#)
        XCTAssertEqual(described.effectiveMessage, "Run the release command")
        XCTAssertEqual(described.effectiveType, "permission")
        XCTAssertEqual(described.effectiveHookType, .permissionRequest)

        let fallback = try decode(#"{"hook_event_name":"PermissionRequest","tool_name":"apply_patch","tool_input":{}}"#)
        XCTAssertEqual(fallback.effectiveMessage, "Approval requested for apply_patch")

        let nonObjectInput = try decode(#"{"hook_event_name":"PermissionRequest","tool_name":"MCP","tool_input":["arg"]}"#)
        XCTAssertEqual(nonObjectInput.effectiveMessage, "Approval requested for MCP")
    }

    func testCodexSubagentStopUsesMessageAndAgentFallback() throws {
        let message = try decode(#"{"hook_event_name":"SubagentStop","agent_type":"reviewer","last_assistant_message":"Review complete."}"#)
        XCTAssertEqual(message.effectiveMessage, "Review complete.")
        XCTAssertEqual(message.effectiveType, "complete")
        XCTAssertEqual(message.effectiveHookType, .subagentStop)

        let fallback = try decode(#"{"hook_event_name":"SubagentStop","agent_type":"reviewer"}"#)
        XCTAssertEqual(fallback.effectiveMessage, "reviewer subagent completed")
    }

    func testClaudePayloadAndTitlesRemainUnchanged() throws {
        let payload = try decode(#"{"hook_event_name":"Notification","notification":{"message":"Claude is waiting"}}"#)
        XCTAssertEqual(payload.effectiveSource, "claude")
        XCTAssertEqual(payload.effectiveMessage, "Claude is waiting")
        XCTAssertEqual(payload.effectiveType, "attention")

        let claude = AgenticNotification(source: .claude, type: .complete, message: "Done", hookType: .stop)
        XCTAssertEqual(claude.displayContent.title, "Claude finished responding")

        let codex = AgenticNotification(source: .codex, type: .complete, message: "Done", hookType: .stop)
        XCTAssertEqual(codex.displayContent.title, "Codex finished responding")
        XCTAssertEqual(codex.displayContent.subtitle, "Codex")
    }

    private func decode(_ json: String) throws -> HookPayload {
        try JSONDecoder().decode(HookPayload.self, from: Data(json.utf8))
    }
}
