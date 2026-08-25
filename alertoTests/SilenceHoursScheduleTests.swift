import XCTest
@testable import Alerto

final class SilenceHoursScheduleTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testDisabledScheduleIsNeverActive() {
        let schedule = SilenceHoursSchedule(isEnabled: false, startMinute: 22 * 60, endMinute: 7 * 60)

        XCTAssertFalse(schedule.isActive(at: date(hour: 23, minute: 30), calendar: calendar))
        XCTAssertFalse(schedule.isActive(at: date(hour: 4, minute: 0), calendar: calendar))
    }

    func testOvernightScheduleIncludesLateNightAndEarlyMorning() {
        let schedule = SilenceHoursSchedule(isEnabled: true, startMinute: 22 * 60, endMinute: 7 * 60)

        XCTAssertFalse(schedule.isActive(at: date(hour: 21, minute: 59), calendar: calendar))
        XCTAssertTrue(schedule.isActive(at: date(hour: 22, minute: 0), calendar: calendar))
        XCTAssertTrue(schedule.isActive(at: date(hour: 23, minute: 59), calendar: calendar))
        XCTAssertTrue(schedule.isActive(at: date(hour: 0, minute: 0), calendar: calendar))
        XCTAssertTrue(schedule.isActive(at: date(hour: 6, minute: 59), calendar: calendar))
        XCTAssertFalse(schedule.isActive(at: date(hour: 7, minute: 0), calendar: calendar))
    }

    func testSameDayScheduleUsesStartInclusiveEndExclusiveRange() {
        let schedule = SilenceHoursSchedule(isEnabled: true, startMinute: 9 * 60, endMinute: 17 * 60)

        XCTAssertFalse(schedule.isActive(at: date(hour: 8, minute: 59), calendar: calendar))
        XCTAssertTrue(schedule.isActive(at: date(hour: 9, minute: 0), calendar: calendar))
        XCTAssertTrue(schedule.isActive(at: date(hour: 16, minute: 59), calendar: calendar))
        XCTAssertFalse(schedule.isActive(at: date(hour: 17, minute: 0), calendar: calendar))
    }

    func testMatchingTimesSilenceAllDay() {
        let schedule = SilenceHoursSchedule(isEnabled: true, startMinute: 8 * 60, endMinute: 8 * 60)

        XCTAssertTrue(schedule.isActive(at: date(hour: 0, minute: 0), calendar: calendar))
        XCTAssertTrue(schedule.isActive(at: date(hour: 12, minute: 0), calendar: calendar))
        XCTAssertTrue(schedule.isActive(at: date(hour: 23, minute: 59), calendar: calendar))
    }

    func testMinutesAreNormalizedIntoOneDay() {
        XCTAssertEqual(SilenceHoursSchedule.normalized(-1), 1439)
        XCTAssertEqual(SilenceHoursSchedule.normalized(1440), 0)
        XCTAssertEqual(SilenceHoursSchedule.normalized(1500), 60)
    }

    private func date(hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 24,
            hour: hour,
            minute: minute
        ))!
    }
}
