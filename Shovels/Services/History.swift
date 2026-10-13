//
//  History.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation

/// One reading of one window, kept for burn-rate estimates and reset alerts.
struct UsageSample: Codable, Sendable, Equatable {
    let provider: String
    /// The window's key, such as "Session" or "GEMINI Weekly".
    let window: String
    let used: Double
    /// When the window resets, in Unix seconds. Identifies the window cycle.
    let resetsAt: Double
    /// When the reading was taken, in Unix seconds.
    let at: Double
}

/// A window that was nearly full and has now reset.
struct ResetEvent: Sendable {
    let provider: ProviderID
    let window: String
}

/// Local usage history in Application Support. Kept for 24 hours and never sent anywhere.
enum UsageHistory {
    private static let keepSeconds: Double = 24 * 3600
    private static let recentSeconds: Double = 30 * 60
    /// Two reset times this close belong to the same window cycle. Antigravity reports "Refreshes in 2h 13m",
    /// so its reset time moves by a minute or so between checks. Every window is far longer than this.
    static let cycleTolerance: Double = 10 * 60

    static var fileURL: URL { ShovelsPaths.support.appending(path: "history.json") }

    static func load() -> [UsageSample] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([UsageSample].self, from: data)) ?? []
    }

    /// Adds one sample per window, saves, and returns windows that reset since the last sample.
    static func record(_ snapshots: [ProviderSnapshot], now: Date, into samples: inout [UsageSample]) -> [ResetEvent] {
        let at = now.timeIntervalSince1970
        var events: [ResetEvent] = []
        for snapshot in snapshots {
            for window in snapshot.windows {
                guard let used = window.usedPercent, let resets = window.resetsAt?.timeIntervalSince1970 else { continue }
                let previous = samples.last { $0.provider == snapshot.provider.rawValue && $0.window == window.key }
                if let previous, previous.used >= 99, resets > previous.resetsAt + cycleTolerance {
                    events.append(ResetEvent(provider: snapshot.provider, window: window.key))
                }
                samples.append(UsageSample(provider: snapshot.provider.rawValue, window: window.key,
                                           used: used, resetsAt: resets, at: at))
            }
        }
        samples = samples.filter { at - $0.at < keepSeconds }
        save(samples)
        return events
    }

    /// Samples for one window cycle, oldest first.
    static func series(_ samples: [UsageSample], provider: ProviderID, window: String, resetsAt: Date) -> [UsageSample] {
        let resets = resetsAt.timeIntervalSince1970
        return samples.filter {
            $0.provider == provider.rawValue && $0.window == window && abs($0.resetsAt - resets) < cycleTolerance
        }
    }

    /// Time until the window reaches 100% at its current pace, or nil without enough data.
    /// A window of five hours or less uses the pace of the last 30 minutes. A longer window, such as weekly,
    /// uses the average pace since its cycle began: a short burst can't last for days, because the 5-hour
    /// limit stops it first. A window with no known length, such as Cursor's, gets no estimate.
    static func runway(_ series: [UsageSample], window: UsageWindow, now: Date) -> TimeInterval? {
        if window.minutes > 300 {
            guard let used = window.usedPercent, used > 0, let resets = window.resetsAt else { return nil }
            let elapsed = Double(window.minutes) * 60 - resets.timeIntervalSince(now)
            // An hour into a cycle, the average is still mostly noise.
            guard elapsed >= 3600 else { return nil }
            return max(0, (100 - used) / (used / elapsed))
        }
        guard window.minutes > 0 else { return nil }
        let recent = series.filter { now.timeIntervalSince1970 - $0.at <= recentSeconds }
        guard let first = recent.first, let last = recent.last,
              last.at - first.at >= 600, last.used > first.used else { return nil }
        let percentPerSecond = (last.used - first.used) / (last.at - first.at)
        return max(0, (100 - last.used) / percentPerSecond)
    }

    private static func save(_ samples: [UsageSample]) {
        do {
            try FileManager.default.createDirectory(at: ShovelsPaths.support, withIntermediateDirectories: true)
            try JSONEncoder().encode(samples).write(to: fileURL, options: .atomic)
        } catch {
            // History is a convenience. A failed write only loses runway estimates after a restart, so it isn't surfaced.
        }
    }
}
