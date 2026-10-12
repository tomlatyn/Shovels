import Foundation

enum ProviderID: String, CaseIterable, Sendable {
    case claudeCode
    case codex

    var displayName: String {
        switch self {
        case .claudeCode: "CLAUDE CODE"
        case .codex: "CODEX"
        }
    }

    var shortName: String {
        switch self {
        case .claudeCode: "CC"
        case .codex: "CX"
        }
    }
}

enum SourceKind: Sendable {
    case localFile
    case statusLineHelper
}

struct UsageWindow: Sendable, Equatable {
    /// Short window name shown in the UI, such as "5H" or "WK".
    var label: String
    /// nil when the source doesn't report a percentage.
    var usedPercent: Double?
    var resetsAt: Date?
}

struct ProviderSnapshot: Sendable, Equatable {
    var provider: ProviderID
    var plan: String?
    var windows: [UsageWindow]
    var asOf: Date
    var source: SourceKind

    /// A snapshot is stale once any of its windows has reset, because the
    /// percentage it holds belongs to the previous window.
    func isStale(at now: Date) -> Bool {
        windows.contains { ($0.resetsAt ?? .distantFuture) <= now }
    }
}

enum Bar {
    /// Ten-cell text bar, such as "█████░░░░░".
    static func text(percent: Double, cells: Int = 10) -> String {
        let filled = min(cells, max(0, Int((percent / 100 * Double(cells)).rounded(.down))))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: cells - filled)
    }
}
