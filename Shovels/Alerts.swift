import Foundation
import UserNotifications

/// Notifications when a window reaches 80% or 95%. Each threshold fires once per window.
enum Alerts {
    static let thresholds: [Int] = [95, 80]
    private static let sentKey = "alertsSent"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Sends alerts for windows that crossed a threshold since the last check.
    /// Sent keys are stored as "provider|window|resetEpoch|threshold", and expired ones are dropped.
    static func check(_ snapshot: ProviderSnapshot, now: Date) {
        let defaults = UserDefaults.standard
        var sent = Set(defaults.stringArray(forKey: sentKey) ?? [])
        sent = sent.filter { key in
            guard let epoch = Double(key.split(separator: "|")[2]) else { return false }
            return epoch > now.timeIntervalSince1970
        }

        for window in snapshot.windows {
            guard let used = window.usedPercent, let resets = window.resetsAt, resets > now else { continue }
            let crossed = thresholds.filter { Double($0) <= used }
            guard let highest = crossed.first else { continue }
            let base = "\(snapshot.provider.rawValue)|\(window.title)|\(Int(resets.timeIntervalSince1970))"
            if sent.contains("\(base)|\(highest)") { continue }
            // Mark every crossed threshold, so a jump from under 80% to over 95% sends one alert, not two.
            for threshold in crossed { sent.insert("\(base)|\(threshold)") }
            post(
                title: snapshot.provider.displayName.capitalized,
                body: "\(window.title) limit at \(Int(used))%. Resets in \(WindowRow.duration(resets.timeIntervalSince(now)))."
            )
        }
        defaults.set(Array(sent), forKey: sentKey)
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
