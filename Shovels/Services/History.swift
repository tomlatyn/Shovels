//
//  History.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation

/// One reading of one window, kept for sparklines, burn-rate estimates, and reset alerts.
struct UsageSample: Codable, Sendable, Equatable {
    let provider: String
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
                let previous = samples.last { $0.provider == snapshot.provider.rawValue && $0.window == window.title }
                if let previous, previous.used >= 99, resets > previous.resetsAt + 60 {
                    events.append(ResetEvent(provider: snapshot.provider, window: window.title))
                }
                samples.append(UsageSample(provider: snapshot.provider.rawValue, window: window.title,
                                           used: used, resetsAt: resets, at: at))
            }
        }
        samples = samples.filter { at - $0.at < keepSeconds }
        save(samples)
        return events
    }

    /// Samples for one window cycle, oldest first.
    static func series(_ samples: [UsageSample], provider: ProviderID, title: String, resetsAt: Date) -> [UsageSample] {
        let resets = resetsAt.timeIntervalSince1970
        return samples.filter {
            $0.provider == provider.rawValue && $0.window == title && abs($0.resetsAt - resets) < 60
        }
    }

    /// Time until the window reaches 100% at the pace of the last 30 minutes, or nil without enough data.
    static func runway(_ series: [UsageSample], now: Date) -> TimeInterval? {
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
            // History is a convenience. A failed write only loses sparklines, so it isn't surfaced.
        }
    }
}
