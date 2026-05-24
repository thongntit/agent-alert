import Foundation

/// User-configured quiet hours window. Stores start/end as integer minutes
/// since midnight so the schedule survives time zone changes and `Date` drift.
struct QuietHours {
    let startMinutes: Int
    let endMinutes: Int

    /// Returns true if `date` falls inside the [start, end) window.
    /// Handles wrap-around when end is earlier than start (e.g. 21:00–09:00).
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard startMinutes != endMinutes else { return false }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if startMinutes < endMinutes {
            return minutes >= startMinutes && minutes < endMinutes
        }
        return minutes >= startMinutes || minutes < endMinutes
    }

    /// Format `minutes` (since midnight) as a localized HH:mm string.
    static func formatted(minutes: Int) -> String {
        let clamped = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60)
        let hour = clamped / 60
        let minute = clamped % 60

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        if let date = Calendar.current.date(from: components) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return formatter.string(from: date)
        }
        return String(format: "%02d:%02d", hour, minute)
    }
}
