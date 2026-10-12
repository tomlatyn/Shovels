import Foundation

enum ClaudeUsageError: Error, Sendable {
    case notInstalled
    case timedOut
    /// Claude Code answered, but not with usage. The first line says why, such as a sign-in prompt.
    case noUsage(firstLine: String)

    var message: String {
        switch self {
        case .notInstalled:
            "Claude Code isn't installed where Shovels can find it."
        case .timedOut:
            "Claude Code took too long to answer."
        case .noUsage(let firstLine):
            firstLine.isEmpty ? "Claude Code didn't return usage." : "Claude Code said: \(firstLine)"
        }
    }
}

/// Reads the same numbers as Claude Code's /usage panel by running the official CLI.
/// Shovels never sees or stores the login token.
enum ClaudeUsageCLI {
    static let candidatePaths = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]

    static func binaryPath() -> String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func fetch(now: Date) throws -> [UsageWindow] {
        guard let path = binaryPath() else { throw ClaudeUsageError.notInstalled }
        let output = try run(path, arguments: ["-p", "/usage"])
        let windows = parse(output, now: now)
        if windows.isEmpty {
            let firstLine = output.components(separatedBy: .newlines).first { !$0.isEmpty } ?? ""
            throw ClaudeUsageError.noUsage(firstLine: firstLine)
        }
        return windows
    }

    /// The subscription tier, such as "pro" or "max", from `claude auth status --json`.
    /// Only that field is read. The email and organization in the output are never kept.
    static func plan() -> String? {
        guard let path = binaryPath(),
              let output = try? run(path, arguments: ["auth", "status", "--json"]),
              let object = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
              let type = object["subscriptionType"] as? String else { return nil }
        return type.uppercased()
    }

    /// Runs the claude CLI. `-p /usage` sends no model request, so it doesn't move the limits.
    private static func run(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = ShovelsPaths.home
        var environment = ProcessInfo.processInfo.environment
        // Apps started from Finder don't get the shell's PATH, and the claude script needs node.
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        let killer = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        if process.terminationReason == .uncaughtSignal {
            throw ClaudeUsageError.timedOut
        }
        return String(decoding: data, as: UTF8.self)
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

    /// Parses reset text such as "Oct 13 at 5am (Europe/Prague)". Returns nil if it doesn't match.
    static func resetDate(_ text: String, now: Date) -> Date? {
        guard let parts = text.firstMatch(of: #/([A-Za-z]{3}) (\d{1,2}) at (\d{1,2})(?::(\d{2}))?\s*(am|pm)/#) else {
            return nil
        }
        let zone = text.firstMatch(of: #/\(([^)]+)\)/#).flatMap { TimeZone(identifier: String($0.1)) } ?? .current

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var year = calendar.component(.year, from: now)

        func date(year: Int) -> Date? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone
            formatter.dateFormat = "MMM d yyyy h:mm a"
            let minute = parts.4.map(String.init) ?? "00"
            return formatter.date(from: "\(parts.1) \(parts.2) \(year) \(parts.3):\(minute) \(parts.5.uppercased())")
        }

        guard var resets = date(year: year) else { return nil }
        // A reset date that is months in the past must be next year's, from a New Year rollover.
        if resets < now.addingTimeInterval(-180 * 86400) {
            year += 1
            resets = date(year: year) ?? resets
        }
        return resets
    }
}
