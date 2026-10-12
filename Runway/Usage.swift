import Foundation

enum ProviderID: Sendable {
    case claudeCode

    var displayName: String {
        switch self {
        case .claudeCode: "CLAUDE CODE"
        }
    }

    var shortName: String {
        switch self {
        case .claudeCode: "CC"
        }
    }
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
    /// Empty until the status line helper has reported limits.
    var windows: [UsageWindow]
    /// When the helper last wrote the limits. nil when there are none.
    var asOf: Date?
    /// Input plus output tokens over the last five hours, from local logs.
    var tokensLast5h: Int?

    /// A window that has reset means the percentage belongs to the previous window.
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
