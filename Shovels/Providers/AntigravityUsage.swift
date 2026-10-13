//
//  AntigravityUsage.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation

enum AntigravityUsageError: Error, Sendable {
    case notInstalled
    case noUsage(String)

    var message: String {
        switch self {
        case .notInstalled:
            "Antigravity's agy CLI isn't installed. Install it, then run 'agy' in Terminal and sign in."
        case .noUsage(let detail):
            detail.isEmpty ? "agy didn't show usage. Run 'agy' in Terminal and check that you're signed in." : detail
        }
    }
}

/// Reads Antigravity's quota from the agy CLI's /usage panel, the same screen you see in Terminal.
enum AntigravityUsage {
    static let candidatePaths = ["/opt/homebrew/bin/agy", "/usr/local/bin/agy"]

    static func snapshot(now: Date) throws -> ProviderSnapshot {
        guard let path = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw AntigravityUsageError.notInstalled
        }
        let screen = try TerminalSession.run(
            path: path,
            directory: ShovelsPaths.home,
            command: "/usage",
            startupSeconds: 10,
            replySeconds: 8,
            blocked: { _ in nil }
        )
        return try parse(screen, now: now)
    }

    /// Reads "Remaining" percentages and "Refreshes in" times. The panel reports what's left, so used is 100 minus remaining.
    static func parse(_ screen: String, now: Date) throws -> ProviderSnapshot {
        var windows: [UsageWindow] = []
        if let match = screen.matches(of: #/Five Hour Limit Remaining[\s\S]*?(\d+(?:\.\d+)?)%[\s\S]*?Refreshes in (?:(\d+)h )?(\d+)m/#).last,
           let remaining = Double(match.1) {
            windows.append(window(title: "Session", minutes: 300, remaining: remaining,
                                  hours: match.2, minutes: match.3, now: now))
        }
        if let match = screen.matches(of: #/Weekly Limit Remaining[\s\S]*?(\d+(?:\.\d+)?)%[\s\S]*?Refreshes in (?:(\d+)h )?(\d+)m/#).last,
           let remaining = Double(match.1) {
            windows.append(window(title: "Weekly", minutes: 10080, remaining: remaining,
                                  hours: match.2, minutes: match.3, now: now))
        }
        guard !windows.isEmpty else {
            throw AntigravityUsageError.noUsage("")
        }
        // The plan appears as "(Google AI Pro)" in the command menu. Read it when it's there.
        let plan = screen.firstMatch(of: #/\(Google AI (\w+)\)/#).map { String($0.1).uppercased() }
        return ProviderSnapshot(provider: .antigravity, plan: plan, windows: windows, asOf: now, tokensLast5h: nil)
    }

    private static func window(title: String, minutes: Int, remaining: Double,
                               hours: Substring?, minutes resetMinutes: Substring, now: Date) -> UsageWindow {
        let untilReset = Double(hours.flatMap { Int($0) } ?? 0) * 3600 + Double(Int(resetMinutes) ?? 0) * 60
        return UsageWindow(
            title: title,
            minutes: minutes,
            usedPercent: min(100, max(0, 100 - remaining)),
            resetsAt: now.addingTimeInterval(untilReset)
        )
    }
}
