//
//  CursorUsage.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation

enum CursorUsageError: ProviderFailure {
    /// Cursor's usage service answered with an error. This is an outage on Cursor's side, not a setup problem.
    case unavailable
    /// Cursor answered with something Shovels can't read.
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Cursor is down right now. Retrying automatically. Status: cursor.com/dashboard?tab=usage"
        case .unreadable:
            "Cursor usage couldn't be read right now. Shovels will try again on its own."
        }
    }

    var needsSetup: Bool { false }
}

/// Reads Cursor usage from the agent CLI's /usage screen, the same screen you see in Terminal.
/// Cursor asks you to trust a folder before it runs. Shovels never answers that question. You answer it once, in Terminal.
enum CursorUsage {
    /// Empty folder Shovels runs the agent in. You trust it once, in Terminal.
    static var workspace: URL {
        ShovelsPaths.support.appending(path: "cursor-workspace", directoryHint: .isDirectory)
    }

    static let trustMessage = "Cursor needs this folder trusted. Run 'agent' in Terminal from ~/Library/Application Support/Shovels/cursor-workspace, choose Trust, then refresh."
    static let notReadyMessage = "Cursor's agent didn't reach its prompt. Run 'agent login' in Terminal and sign in, then refresh."

    static func snapshot(now: Date) throws -> ProviderSnapshot {
        let path = try CLILocator.locate("agent")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let screen = try TerminalSession.run(
            path: path,
            directory: workspace,
            command: "/usage",
            startupSeconds: 15,
            replySeconds: 30,
            blocked: { text in
                text.contains("Trust this workspace") || text.contains("Workspace Trust Required") ? trustMessage : nil
            },
            ready: { $0.contains("Plan, search") },
            notReady: notReadyMessage,
            replyUntil: { text in text.contains("Usage •") || text.contains("Failed to load usage data") }
        )
        return try parse(screen, now: now)
    }

    /// Reads the plan and the Included, Auto, and API usage from the /usage panel.
    /// The panel repaints, so the last complete reading wins.
    static func parse(_ screen: String, now: Date) throws -> ProviderSnapshot {
        guard let plan = screen.matches(of: #/Usage • (\w+)/#).last.map({ String($0.1).uppercased() }) else {
            if screen.contains("Failed to load usage data") {
                throw CursorUsageError.unavailable
            }
            throw CursorUsageError.unreadable
        }
        let resets = screen.matches(of: #/Resets (\w{3}) (\d{1,2})/#).last.flatMap { match -> Date? in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM d yyyy"
            var calendar = Calendar.current
            calendar.timeZone = .current
            let year = calendar.component(.year, from: now)
            var date = formatter.date(from: "\(match.1) \(match.2) \(year)")
            if let candidate = date, candidate < now.addingTimeInterval(-180 * 86400) {
                date = formatter.date(from: "\(match.1) \(match.2) \(year + 1)")
            }
            return date
        }
        var windows: [UsageWindow] = []
        for (title, pattern) in [("Included", #/Included\s+(\d+)% used/#), ("Auto", #/Auto\s+(\d+)% used/#), ("API", #/API\s+(\d+)% used/#)] {
            if let match = screen.matches(of: pattern).last, let used = Double(match.1) {
                // minutes 0 keeps the panel's own name, since Cursor's windows are monthly with no named length.
                windows.append(UsageWindow(title: title, minutes: 0, usedPercent: used, resetsAt: resets))
            }
        }
        guard !windows.isEmpty else {
            throw CursorUsageError.unreadable
        }
        return ProviderSnapshot(provider: .cursor, plan: plan, windows: windows, asOf: now, tokensLast5h: nil)
    }
}
