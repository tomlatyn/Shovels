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
    /// Sent keys are "provider|window|resetEpoch|threshold". A key matches any reset time within
    /// `UsageHistory.cycleTolerance`, because some providers report the reset time only to the minute.
    /// Expired keys are dropped.
    static func check(_ snapshot: ProviderSnapshot, now: Date, history: [UsageSample]) {
        let defaults = UserDefaults.standard
        let stored = (defaults.stringArray(forKey: sentKey) ?? []).compactMap(SentAlert.init(key:))
        let (windows, sent) = due(snapshot, now: now, sent: stored)

        for window in windows {
            guard let used = window.usedPercent, let resets = window.resetsAt else { continue }
            let untilReset = resets.timeIntervalSince(now)
            var body = "\(window.title) limit at \(Int(used))%. Resets in \(Formatting.duration(untilReset))."
            let series = UsageHistory.series(history, provider: snapshot.provider, window: window.key, resetsAt: resets)
            if let runway = UsageHistory.runway(series, window: window, now: now), runway < untilReset {
                body += " At this pace: full in \(Formatting.duration(runway))."
            }
            let name: [String] = [snapshot.provider.displayName.capitalized, window.group, window.title].compactMap { $0 }
            post(title: name.joined(separator: " · "), body: body)
        }
        defaults.set(sent.map(\.key), forKey: sentKey)
    }

    /// The windows that need an alert now, and the updated list of sent alerts. Sends nothing.
    static func due(_ snapshot: ProviderSnapshot, now: Date, sent stored: [SentAlert]) -> (windows: [UsageWindow], sent: [SentAlert]) {
        let tolerance = UsageHistory.cycleTolerance
        var sent = stored.filter { $0.resetsAt + tolerance > now.timeIntervalSince1970 }
        var windows: [UsageWindow] = []
        for window in snapshot.windows {
            guard let used = window.usedPercent, let resets = window.resetsAt, resets > now else { continue }
            let crossed = thresholds.filter { Double($0) <= used }
            guard let highest = crossed.first else { continue }
            let epoch = resets.timeIntervalSince1970
            let alreadySent = sent.contains {
                $0.provider == snapshot.provider.rawValue && $0.window == window.key
                    && $0.threshold == highest && abs($0.resetsAt - epoch) < tolerance
            }
            if alreadySent { continue }
            // Mark every crossed threshold, so a jump from under 80% to over 95% sends one alert, not two.
            for threshold in crossed {
                sent.append(SentAlert(provider: snapshot.provider.rawValue, window: window.key, resetsAt: epoch, threshold: threshold))
            }
            windows.append(window)
        }
        return (windows, sent)
    }

    /// One alert already sent, stored as "provider|window|resetEpoch|threshold".
    struct SentAlert: Equatable {
        let provider: String
        let window: String
        let resetsAt: Double
        let threshold: Int

        init(provider: String, window: String, resetsAt: Double, threshold: Int) {
            self.provider = provider
            self.window = window
            self.resetsAt = resetsAt
            self.threshold = threshold
        }

        init?(key: String) {
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 4, let epoch = Double(parts[2]), let threshold = Int(parts[3]) else { return nil }
            self.init(provider: String(parts[0]), window: String(parts[1]), resetsAt: epoch, threshold: threshold)
        }

        var key: String { "\(provider)|\(window)|\(Int(resetsAt))|\(threshold)" }
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
