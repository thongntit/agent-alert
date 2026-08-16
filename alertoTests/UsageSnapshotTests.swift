import XCTest
@testable import Alerto

final class UsageSnapshotTests: XCTestCase {
    func testUsesOpenUsageBrandColors() {
        XCTAssertEqual(UsageProvider.claude.brandColorHex, "#DE7356")
        XCTAssertEqual(UsageProvider.codex.brandColorHex, "#10A37F")
    }

    func testMapsClaudeRemainingSessionAndWeeklyLimits() throws {
        let usage = try UsageResponseMapper.claude(data: Data(#"""
        {
          "five_hour": { "utilization": 5, "resets_at": "2026-08-07T09:00:00.103Z" },
          "seven_day": { "utilization": 1, "resets_at": "2026-08-14T04:00:00.103Z" }
        }
        """#.utf8))

        XCTAssertEqual(usage.provider, .claude)
        XCTAssertEqual(usage.limits.map(\.formattedRemaining), ["95% left", "99% left"])
        XCTAssertNotNil(usage.limits.first?.resetsAt)
    }

    func testMapsCodexWindowsByDurationInsteadOfSlot() throws {
        let usage = try UsageResponseMapper.codex(data: Data(#"""
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 63,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 120
            }
          }
        }
        """#.utf8), now: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(usage.plan, "Plus")
        XCTAssertEqual(usage.limits.map(\.label), ["Weekly"])
        XCTAssertEqual(usage.limits.first?.remainingPercent, 37)
        XCTAssertEqual(usage.limits.first?.resetsAt, Date(timeIntervalSince1970: 1_120))
    }

    func testRejectsMissingCodexLimits() {
        XCTAssertThrowsError(try UsageResponseMapper.codex(data: Data(#"{"rate_limit":{}}"#.utf8))) { error in
            XCTAssertEqual(error as? UsageFetchError, .invalidResponse(.codex))
        }
    }
}
