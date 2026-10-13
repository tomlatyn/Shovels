//
//  ParserTests.swift
//  ShovelsTests
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation
import Testing

/// 13 Oct 2026, 11:50 in Prague, when the fixtures were captured.
private let captured = Date(timeIntervalSince1970: 1_791_885_000)

private func prague(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, year: Int = 2026) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

struct ClaudeParserTests {
    @Test func readsSessionAndWeekly() {
        let windows = ClaudeUsageCLI.parse(Fixtures.claude, now: captured)
        #expect(windows.map(\.title) == ["Session", "Weekly"])
        #expect(windows.map(\.usedPercent) == [8, 7])
        #expect(windows[0].resetsAt == prague(10, 13, 16, 30))
        #expect(windows[1].resetsAt == prague(10, 14, 1))
    }

    @Test func noUsageLinesGivesNoWindows() {
        #expect(ClaudeUsageCLI.parse("Please run /login", now: captured).isEmpty)
    }

    @Test func resetWithoutDateIsTheNextTimeThatClockTimeComes() {
        let later = ClaudeUsageCLI.resetDate("4:30pm (Europe/Prague)", now: captured)
        #expect(later == prague(10, 13, 16, 30))
        let tomorrow = ClaudeUsageCLI.resetDate("9am (Europe/Prague)", now: captured)
        #expect(tomorrow == prague(10, 14, 9))
    }

    @Test func noonAndMidnight() {
        #expect(ClaudeUsageCLI.resetDate("Oct 14 at 12pm (Europe/Prague)", now: captured) == prague(10, 14, 12))
        #expect(ClaudeUsageCLI.resetDate("Oct 14 at 12am (Europe/Prague)", now: captured) == prague(10, 14, 0))
    }

    @Test func januaryResetSeenInDecemberIsNextYear() {
        let december = prague(12, 30, 12, year: 2026)
        #expect(ClaudeUsageCLI.resetDate("Jan 2 at 5am (Europe/Prague)", now: december) == prague(1, 2, 5, year: 2027))
    }
}

struct CodexParserTests {
    @Test func readsMonthlyWindowAndPlan() throws {
        let reply = try #require(JSONSerialization.jsonObject(with: Data(Fixtures.codex.utf8)) as? [String: Any])
        let snapshot = try CodexUsage.parse(reply, now: captured)
        #expect(snapshot.plan == "FREE")
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].title == "Monthly")
        #expect(snapshot.windows[0].minutes == 43200)
        #expect(snapshot.windows[0].usedPercent == 0)
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_794_478_346))
    }

    @Test func replyWithoutLimitsThrows() {
        #expect(throws: CodexUsageError.self) { try CodexUsage.parse(["result": [:]], now: captured) }
    }
}

struct AntigravityParserTests {
    @Test func readsBothQuotaGroups() throws {
        let snapshot = try AntigravityUsage.parse(Fixtures.antigravity, now: captured)
        #expect(snapshot.plan == "PRO")
        #expect(snapshot.windows.map(\.key) == [
            "GEMINI Session", "GEMINI Weekly", "CLAUDE AND GPT Session", "CLAUDE AND GPT Weekly",
        ])
        #expect(snapshot.windows.map(\.usedPercent) == [0, 48.7, 0, 1.45])
    }

    @Test func fullWindowHasNoResetTimeAndOthersUseTheirOwn() throws {
        let windows = try AntigravityUsage.parse(Fixtures.antigravity, now: captured).windows
        #expect(windows[0].resetsAt == nil)
        #expect(windows[1].resetsAt == captured.addingTimeInterval(50 * 3600 + 19 * 60))
        #expect(windows[3].resetsAt == captured.addingTimeInterval(157 * 3600 + 55 * 60))
    }

    @Test func refreshDelayAcceptsDaysHoursAndMinutes() {
        #expect(AntigravityUsage.refreshDelay(in: "Refreshes in 2d 3h") == 2 * 86400 + 3 * 3600)
        #expect(AntigravityUsage.refreshDelay(in: "Refreshes in 45m") == 45 * 60)
        #expect(AntigravityUsage.refreshDelay(in: "Quota available") == nil)
    }

    @Test func screenWithoutPanelThrows() {
        #expect(throws: AntigravityUsageError.self) { try AntigravityUsage.parse("? for shortcuts", now: captured) }
    }
}

struct CursorParserTests {
    @Test func readsPlanWindowsAndReset() throws {
        let snapshot = try CursorUsage.parse(Fixtures.cursor, now: captured)
        #expect(snapshot.plan == "PRO")
        #expect(snapshot.windows.map(\.title) == ["Included", "Auto", "API"])
        #expect(snapshot.windows.map(\.usedPercent) == [88, 87, 100])
        let reset = try #require(snapshot.windows[0].resetsAt)
        #expect(Calendar.current.dateComponents([.month, .day], from: reset) == DateComponents(month: 10, day: 18))
    }

    @Test func failedLoadIsAnOutage() {
        #expect(throws: CursorUsageError.unavailable) {
            try CursorUsage.parse("Loading usage data...\nFailed to load usage data", now: captured)
        }
    }
}

struct TerminalCleanTests {
    @Test func removesColorAndCursorCodes() {
        let raw = Data("\u{1B}[32mGEMINI MODELS\u{1B}[0m\r\u{1B}]0;title\u{07}done".utf8)
        #expect(TerminalSession.clean(raw) == "GEMINI MODELS\ndone")
    }
}
