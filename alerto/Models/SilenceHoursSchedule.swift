import Foundation

struct SilenceHoursSchedule: Equatable {
    static let defaultStartMinute = 22 * 60
    static let defaultEndMinute = 7 * 60

    let isEnabled: Bool
    let startMinute: Int
    let endMinute: Int

    func isActive(at date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard isEnabled else { return false }

        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return false }
        let currentMinute = hour * 60 + minute
        let start = Self.normalized(startMinute)
        let end = Self.normalized(endMinute)

        if start == end {
            return true
        }
        if start < end {
            return currentMinute >= start && currentMinute < end
        }
        return currentMinute >= start || currentMinute < end
    }

    static func normalized(_ minute: Int) -> Int {
        let minutesPerDay = 24 * 60
        return ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay
    }
}
