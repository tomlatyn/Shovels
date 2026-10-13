//
//  ClaudeUsage.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation

enum ClaudeUsageError: ProviderFailure {
    case timedOut
    /// Claude Code answered, but not with usage. The first line says why, such as a sign-in prompt.
    case noUsage(firstLine: String)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "Claude Code took too long to answer. Shovels will try again."
        case .noUsage(let firstLine):
            firstLine.isEmpty
                ? "Claude Code didn't return usage. Run 'claude' in Terminal and check that you're signed in."
                : "Claude Code said: \(firstLine)"
        }
    }

    var needsSetup: Bool {
        switch self {
        case .timedOut: false
        case .noUsage: true
        }
    }
}

/// Reads the same numbers as Claude Code's /usage panel by running the official CLI.
/// Shovels never sees or stores the login token.
enum ClaudeUsageCLI {
    /// Keeps each check out of `claude --resume` and skips starting MCP servers.
    static let quietFlags = ["--no-session-persistence", "--strict-mcp-config"]

    static func fetch(path: String, now: Date) throws -> [UsageWindow] {
        var output = try run(path, arguments: ["-p", "/usage"] + quietFlags)
        // Older Claude Code versions don't know the quiet flags. Retry without them.
        if output.status != 0, (output.stderr + output.stdout).localizedCaseInsensitiveContains("unknown option") {
            output = try run(path, arguments: ["-p", "/usage"])
        }
        let windows = parse(output.stdout, now: now)
        if windows.isEmpty {
            throw ClaudeUsageError.noUsage(firstLine: firstLine(output.stdout) ?? firstLine(output.stderr) ?? "")
        }
        return windows
    }

    /// The subscription tier, such as "pro" or "max", from `claude auth status --json`.
    /// Only that field is read. The email and organization in the output are never kept.
    static func plan(path: String) -> String? {
        guard let output = try? run(path, arguments: ["auth", "status", "--json"]),
              let object = try? JSONSerialization.jsonObject(with: Data(output.stdout.utf8)) as? [String: Any],
              let type = object["subscriptionType"] as? String else { return nil }
        return type.uppercased()
    }

    /// Runs the claude CLI. `-p /usage` is a local command, so it doesn't send a model request.
    private static func run(_ path: String, arguments: [String]) throws -> CommandRunner.Output {
        let output = try CommandRunner.run(path: path, arguments: arguments, directory: ShovelsPaths.home, timeout: 30)
        if output.timedOut { throw ClaudeUsageError.timedOut }
        return output
    }

    private static func firstLine(_ text: String) -> String? {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// Parses lines such as "Current session: 20% used · resets Oct 13 at 5am (Europe/Prague)".
    static func parse(_ output: String, now: Date) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        for line in output.components(separatedBy: .newlines) {
            if let match = line.firstMatch(of: #/Current session: (\d+)% used · resets (.+)/#),
               let percent = Double(match.1) {
                windows.append(UsageWindow(title: "Session", minutes: 300, usedPercent: percent, resetsAt: resetDate(String(match.2), now: now)))
            } else if let match = line.firstMatch(of: #/Current week \(all models\): (\d+)% used · resets (.+)/#),
                      let percent = Double(match.1) {
                windows.append(UsageWindow(title: "Weekly", minutes: 10080, usedPercent: percent, resetsAt: resetDate(String(match.2), now: now)))
            }
        }
        return windows
    }

    /// Parses reset text such as "Oct 13 at 5am (Europe/Prague)", or "4:30pm (Europe/Prague)" with no date,
    /// which means the next time the clock shows that time. Returns nil if it doesn't match.
    static func resetDate(_ text: String, now: Date) -> Date? {
        guard let parts = text.firstMatch(of: #/(?:([A-Za-z]{3}) (\d{1,2}),? (?:at )?)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)/#) else {
            return nil
        }
        let zone = text.firstMatch(of: #/\(([^)]+)\)/#).flatMap { TimeZone(identifier: String($0.1)) } ?? .current

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard var hour = Int(parts.3), hour >= 1, hour <= 12 else { return nil }
        hour = hour % 12 + (parts.5 == "pm" ? 12 : 0)
        let minute = parts.4.flatMap { Int($0) } ?? 0

        guard let monthName = parts.1, let day = parts.2.flatMap({ Int($0) }) else {
            // Time only: today at that time, or tomorrow if it has passed.
            guard let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
            return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
        }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard let month = months.firstIndex(of: monthName.lowercased()).map({ $0 + 1 }) else { return nil }

        let year = calendar.component(.year, from: now)
        func date(year: Int) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
        }
        guard let resets = date(year: year) else { return nil }
        // A reset date that is months in the past must be next year's, from a New Year rollover.
        if resets < now.addingTimeInterval(-180 * 86400) {
            return date(year: year + 1) ?? resets
        }
        return resets
    }
}
