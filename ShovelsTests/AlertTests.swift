//
//  AlertTests.swift
//  ShovelsTests
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation
import Testing

private let start = Date(timeIntervalSince1970: 1_791_885_000)

private func snapshot(_ used: Double, resetsIn seconds: TimeInterval, at now: Date,
                      provider: ProviderID = .antigravity, group: String? = "GEMINI") -> ProviderSnapshot {
    ProviderSnapshot(
        provider: provider, plan: nil,
        windows: [UsageWindow(title: "Weekly", group: group, minutes: 10080, usedPercent: used,
                              resetsAt: now.addingTimeInterval(seconds))],
        asOf: now, tokensLast5h: nil
    )
}

struct AlertTests {
    @Test func crossingEightyAlertsOnce() {
        let first = Alerts.due(snapshot(82, resetsIn: 3600, at: start), now: start, sent: [])
        #expect(first.windows.count == 1)
        let later = start.addingTimeInterval(300)
        let second = Alerts.due(snapshot(83, resetsIn: 3300, at: later), now: later, sent: first.sent)
        #expect(second.windows.isEmpty)
    }

    /// Antigravity's "Refreshes in 2h 13m" moves the reset time by up to a minute between checks.
    @Test func resetTimeJitterDoesNotRepeatTheAlert() {
        let first = Alerts.due(snapshot(85, resetsIn: 7980, at: start), now: start, sent: [])
        var sent = first.sent
        for check in 1...6 {
            let now = start.addingTimeInterval(Double(check) * 300)
            // The true reset is fixed; the reported one lands up to 75 seconds early.
            let jitter = Double(check % 3) * -37.5
            let due = Alerts.due(snapshot(85, resetsIn: 7980 - Double(check) * 300 + jitter, at: now), now: now, sent: sent)
            #expect(due.windows.isEmpty, "check \(check) alerted again")
            sent = due.sent
        }
    }

    @Test func jumpPastBothThresholdsSendsOneAlert() {
        let due = Alerts.due(snapshot(97, resetsIn: 3600, at: start), now: start, sent: [])
        #expect(due.windows.count == 1)
        #expect(Set(due.sent.map(\.threshold)) == [80, 95])
        let later = start.addingTimeInterval(300)
        #expect(Alerts.due(snapshot(98, resetsIn: 3300, at: later), now: later, sent: due.sent).windows.isEmpty)
    }

    @Test func nextCycleAlertsAgain() {
        let first = Alerts.due(snapshot(90, resetsIn: 600, at: start), now: start, sent: [])
        let nextCycle = start.addingTimeInterval(3600)
        let due = Alerts.due(snapshot(90, resetsIn: 7 * 86400, at: nextCycle), now: nextCycle, sent: first.sent)
        #expect(due.windows.count == 1)
    }

    @Test func groupsAreSeparateWindows() {
        let gemini = Alerts.due(snapshot(90, resetsIn: 3600, at: start, group: "GEMINI"), now: start, sent: [])
        let other = Alerts.due(snapshot(90, resetsIn: 3600, at: start, group: "CLAUDE AND GPT"), now: start, sent: gemini.sent)
        #expect(other.windows.count == 1)
    }

    @Test func sentKeysRoundTrip() {
        let alert = Alerts.SentAlert(provider: "antigravity", window: "GEMINI Weekly", resetsAt: 1_791_900_000, threshold: 80)
        #expect(Alerts.SentAlert(key: alert.key) == alert)
        #expect(Alerts.SentAlert(key: "broken") == nil)
    }
}

struct HistoryTests {
    private func sample(_ used: Double, resetsAt: Double, at: Double) -> UsageSample {
        UsageSample(provider: "antigravity", window: "GEMINI Weekly", used: used, resetsAt: resetsAt, at: at)
    }

    @Test func seriesToleratesResetJitter() {
        let reset = start.addingTimeInterval(7200).timeIntervalSince1970
        let samples = [
            sample(10, resetsAt: reset, at: 0),
            sample(12, resetsAt: reset - 55, at: 300),
            sample(14, resetsAt: reset + 20, at: 600),
            sample(1, resetsAt: reset + 7 * 86400, at: 900),
        ]
        let series = UsageHistory.series(samples, provider: .antigravity, window: "GEMINI Weekly",
                                         resetsAt: Date(timeIntervalSince1970: reset))
        #expect(series.map(\.used) == [10, 12, 14])
    }

    private func window(minutes: Int, used: Double, resetsIn seconds: TimeInterval) -> UsageWindow {
        UsageWindow(title: "W", minutes: minutes, usedPercent: used, resetsAt: start.addingTimeInterval(seconds))
    }

    @Test func sessionRunwayNeedsTenMinutesOfRisingUsage() {
        let now = start.timeIntervalSince1970
        let reset = now + 3 * 3600
        let session = window(minutes: 300, used: 20, resetsIn: 3 * 3600)
        let short = [sample(10, resetsAt: reset, at: now - 300), sample(20, resetsAt: reset, at: now)]
        #expect(UsageHistory.runway(short, window: session, now: start) == nil)
        let rising = [sample(10, resetsAt: reset, at: now - 1200), sample(20, resetsAt: reset, at: now)]
        // 10 points in 20 minutes leaves 80 points: 160 minutes.
        #expect(UsageHistory.runway(rising, window: session, now: start) == 160 * 60)
    }

    /// The screenshot case: weekly at 12% with 12.5 hours left. A 30-minute burst said "full in 12 hours".
    @Test func weeklyRunwayUsesTheWholeCycle() throws {
        let now = start.timeIntervalSince1970
        let weekly = window(minutes: 10080, used: 12, resetsIn: 12.5 * 3600)
        let burst = [sample(10, resetsAt: now + 45000, at: now - 1800), sample(12, resetsAt: now + 45000, at: now)]
        let runway = try #require(UsageHistory.runway(burst, window: weekly, now: start))
        #expect(runway > 12.5 * 3600)
        // 50% three days in fills in another three days.
        let busy = window(minutes: 10080, used: 50, resetsIn: 4 * 86400)
        #expect(UsageHistory.runway([], window: busy, now: start) == 3 * 86400)
    }

    @Test func noRunwayWithoutAWindowLength() {
        let cursor = window(minutes: 0, used: 88, resetsIn: 5 * 86400)
        #expect(UsageHistory.runway([], window: cursor, now: start) == nil)
    }
}

struct FormattingTests {
    @Test func durations() {
        #expect(Formatting.duration(30) == "1 min")
        #expect(Formatting.duration(3600 + 120) == "1 hour 2 min")
        #expect(Formatting.duration(2 * 86400 + 3 * 3600) == "2 days 3 hours")
    }
}
