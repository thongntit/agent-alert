import Foundation

struct NotificationDeduplicator {
    private var lastSeenAtByFingerprint: [String: Date] = [:]

    mutating func isDuplicate(
        fingerprint: String,
        at now: Date = Date(),
        within window: TimeInterval
    ) -> Bool {
        guard window > 0 else { return false }

        let lastSeenAt = lastSeenAtByFingerprint.updateValue(now, forKey: fingerprint)
        guard let lastSeenAt else { return false }

        return now.timeIntervalSince(lastSeenAt) <= window
    }
}
