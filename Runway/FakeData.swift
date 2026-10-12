import Foundation

/// Sample data for the skeleton. Replaced by real providers in M2 and M3.
enum FakeData {
    static func snapshots(now: Date = .now) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                provider: .claudeCode,
                plan: "MAX",
                windows: [
                    UsageWindow(label: "5H", usedPercent: 47, resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60)),
                    UsageWindow(label: "WK", usedPercent: 31, resetsAt: now.addingTimeInterval(3 * 86400)),
                ],
                asOf: now.addingTimeInterval(-180),
                source: .statusLineHelper
            ),
            // Both windows have reset, so this card shows the STALE state.
            ProviderSnapshot(
                provider: .codex,
                plan: "PLUS",
                windows: [
                    UsageWindow(label: "5H", usedPercent: 80, resetsAt: now.addingTimeInterval(-30 * 86400)),
                    UsageWindow(label: "WK", usedPercent: 24, resetsAt: now.addingTimeInterval(-25 * 86400)),
                ],
                asOf: now.addingTimeInterval(-32 * 86400),
                source: .localFile
            ),
        ]
    }
}
