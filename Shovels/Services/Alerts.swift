//
//  Alerts.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import AppKit
import Foundation
import UserNotifications

/// Notifications for limits: 80% and 95% thresholds, and resets after a nearly full window.
enum Alerts {
    static let thresholds: [Int] = [95, 80]
    private static let sentKey = "alertsSent"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Sends alerts for windows that crossed a threshold since the last check.
    /// Sent keys are "provider|window|resetEpoch|threshold". Expired keys are dropped.
    static func check(_ snapshot: ProviderSnapshot, now: Date, history: [UsageSample]) {
        let defaults = UserDefaults.standard
        var sent = Set(defaults.stringArray(forKey: sentKey) ?? [])
        sent = sent.filter { key in
            let parts = key.split(separator: "|")
            guard parts.count == 4, let epoch = Double(parts[2]) else { return false }
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

            let untilReset = resets.timeIntervalSince(now)
            var body = "\(window.title) limit at \(Int(used))%. Resets in \(Formatting.duration(untilReset))."
            let series = UsageHistory.series(history, provider: snapshot.provider, title: window.title, resetsAt: resets)
            if let runway = UsageHistory.runway(series, now: now), runway < untilReset {
                body += " At this pace: full in \(Formatting.duration(runway))."
            }
            post(title: "\(snapshot.provider.displayName.capitalized) · \(window.title)", body: body)
        }
        defaults.set(Array(sent), forKey: sentKey)
    }

    /// Tells you a nearly full window has reset.
    static func reset(_ event: ResetEvent) {
        post(
            title: "\(event.provider.displayName.capitalized) · \(event.window)",
            body: "\(event.window) window reset. You have full capacity again."
        )
    }

    /// Sends a test alert. Asks for permission first if macOS hasn't decided yet,
    /// and opens Notifications settings if it was turned off. Returns a line for the settings screen.
    static func test() async -> String {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            post(title: "Shovels", body: "Test alert. Notifications are working.")
            return "Test alert sent."
        case .denied:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
            return "Notifications are off for Shovels. Turn them on in System Settings › Notifications."
        default:
            return "Allow notifications for Shovels when macOS asks, then test again."
        }
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
