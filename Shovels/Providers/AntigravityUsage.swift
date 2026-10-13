//
//  AntigravityUsage.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation

enum AntigravityUsageError: ProviderFailure {
    /// agy showed something other than the quota panel Shovels knows.
    case unreadable

    var errorDescription: String? {
        "Antigravity usage couldn't be read right now. Shovels will try again on its own."
    }

    var needsSetup: Bool { false }
}

/// Reads Antigravity's quota from the agy CLI's /usage panel, the same screen you see in Terminal.
/// agy runs in its own empty folder, which you trust once in Terminal. Shovels never answers that question.
enum AntigravityUsage {
    /// Empty folder Shovels runs agy in. You trust it once, in Terminal.
    static var workspace: URL {
        ShovelsPaths.support.appending(path: "antigravity-workspace", directoryHint: .isDirectory)
    }

    static let trustMessage = "Antigravity needs this folder trusted. Run 'agy' in Terminal from ~/Library/Application Support/Shovels/antigravity-workspace, choose Yes, then refresh."
    static let notReadyMessage = "agy didn't reach its prompt. Run 'agy' in Terminal and sign in, then refresh."

    /// `folder` is the workspace agy runs in. Only tests pass another one.
    static func snapshot(now: Date, folder: URL = workspace) throws -> ProviderSnapshot {
        let path = try CLILocator.locate("agy")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let screen = try TerminalSession.run(
            path: path,
            directory: folder,
            command: "/usage",
            startupSeconds: 15,
            replySeconds: 10,
            blocked: { text in
                text.contains("Do you trust the contents of this project") || text.contains("I trust this folder") ? trustMessage : nil
            },
            ready: { $0.contains("? for shortcuts") },
            notReady: notReadyMessage,
            replyUntil: { text in
                // The key hints at the bottom of the panel are drawn last.
                guard let panel = text.range(of: "Models & Quota", options: .backwards) else { return false }
                return text[panel.upperBound...].contains("Scroll")
            }
        )
        return try parse(screen, now: now)
    }

    /// Reads "Remaining" percentages and "Refreshes in" times for each quota group, such as
    /// "GEMINI MODELS" and "CLAUDE AND GPT MODELS". The panel reports what's left, so used is 100 minus remaining.
    /// A full window says "Quota available" with no refresh time.
    static func parse(_ screen: String, now: Date) throws -> ProviderSnapshot {
        // The panel repaints, so only the last one counts.
        let panel = screen.range(of: "Models & Quota", options: .backwards).map { screen[$0.upperBound...] } ?? screen[...]

        let headers = panel.matches(of: #/^\s*([A-Z][A-Z0-9 &+\/-]*?) MODELS\s*$/#.anchorsMatchLineEndings())
        var sections: [(group: String?, text: Substring)] = []
        if headers.isEmpty {
            sections = [(nil, panel)]
        } else {
            for (index, header) in headers.enumerated() {
                let end = index + 1 < headers.count ? headers[index + 1].range.lowerBound : panel.endIndex
                sections.append((String(header.1), panel[header.range.upperBound..<end]))
            }
        }

        var windows: [UsageWindow] = []
        for section in sections {
            let labels = section.text.matches(of: #/(Weekly|Five Hour) Limit Remaining/#)
            var groupWindows: [UsageWindow] = []
            for (index, label) in labels.enumerated() {
                let end = index + 1 < labels.count ? labels[index + 1].range.lowerBound : section.text.endIndex
                let block = section.text[label.range.upperBound..<end]
                guard let match = block.firstMatch(of: #/(\d+(?:\.\d+)?)%/#), let remaining = Double(match.1) else { continue }
                let isWeekly = label.1 == "Weekly"
                groupWindows.append(UsageWindow(
                    title: isWeekly ? "Weekly" : "Session",
                    group: section.group,
                    minutes: isWeekly ? 10080 : 300,
                    usedPercent: min(100, max(0, ((100 - remaining) * 100).rounded() / 100)),
                    resetsAt: refreshDelay(in: block).map { now.addingTimeInterval($0) }
                ))
            }
            // The panel lists Weekly first. Session leads, so the menu bar shows the 5-hour window.
            windows += groupWindows.sorted { $0.minutes < $1.minutes }
        }
        guard !windows.isEmpty else { throw AntigravityUsageError.unreadable }

        // The plan appears as "(Google AI Pro)" next to the account. Read it when it's there.
        let plan = screen.firstMatch(of: #/\(Google AI (\w+)\)/#).map { String($0.1).uppercased() }
        return ProviderSnapshot(provider: .antigravity, plan: plan, windows: windows, asOf: now, tokensLast5h: nil)
    }

    /// Seconds in text such as "Refreshes in 157h 55m" or "Refreshes in 2d 3h". nil when there's no refresh time.
    static func refreshDelay(in text: Substring) -> TimeInterval? {
        guard let phrase = text.firstMatch(of: #/Refreshes in ((?:\d+\s*[dhm]\s*)+)/#) else { return nil }
        var seconds: TimeInterval = 0
        for part in phrase.1.matches(of: #/(\d+)\s*([dhm])/#) {
            let value = Double(part.1) ?? 0
            switch part.2 {
            case "d": seconds += value * 86400
            case "h": seconds += value * 3600
            default: seconds += value * 60
            }
        }
        return seconds
    }
}
