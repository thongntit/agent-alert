import XCTest
@testable import Alerto

final class NotificationDeduplicatorTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let window: TimeInterval = 5

    func testInterleavedNotificationDoesNotResetAnotherFingerprint() {
        var deduplicator = NotificationDeduplicator()

        XCTAssertFalse(deduplicator.isDuplicate(fingerprint: "A", at: start, within: window))
        XCTAssertFalse(deduplicator.isDuplicate(fingerprint: "B", at: start.addingTimeInterval(1), within: window))
        XCTAssertTrue(deduplicator.isDuplicate(fingerprint: "A", at: start.addingTimeInterval(2), within: window))
    }

    func testSuppressedArrivalAdvancesLastSeenTime() {
        var deduplicator = NotificationDeduplicator()

        XCTAssertFalse(deduplicator.isDuplicate(fingerprint: "A", at: start, within: window))
        XCTAssertTrue(deduplicator.isDuplicate(fingerprint: "A", at: start.addingTimeInterval(4), within: window))
        XCTAssertTrue(deduplicator.isDuplicate(fingerprint: "A", at: start.addingTimeInterval(8), within: window))
    }
}
