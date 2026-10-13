import Foundation

enum ProviderID: String, Sendable, CaseIterable {
    case claudeCode
    case codex
    case antigravity
    case cursor

    var displayName: String {
        switch self {
        case .claudeCode: "CLAUDE CODE"
        case .codex: "CODEX"
        case .antigravity: "ANTIGRAVITY"
        case .cursor: "CURSOR"
        }
    }

    var shortName: String {
        switch self {
        case .claudeCode: "CC"
        case .codex: "CX"
        case .antigravity: "AG"
        case .cursor: "CU"
        }
    }
}

struct UsageWindow: Sendable, Equatable {
    /// Name shown in the UI, such as "Session", "Weekly", or "Monthly".
    var title: String
    /// Length of the window in minutes. 300 is the 5-hour session window.
    var minutes: Int
    /// nil when the source doesn't report a percentage.
    var usedPercent: Double?
    var resetsAt: Date?
}

struct ProviderSnapshot: Sendable, Equatable {
    var provider: ProviderID
    var plan: String?
    /// The provider's windows, in the order it reports them. The first one leads.
    var windows: [UsageWindow]
    /// When the reading was taken.
    var asOf: Date?
    /// Input plus output tokens over the last five hours, from local logs. Claude Code only.
    var tokensLast5h: Int?

    /// A window that has reset means the percentage belongs to the previous window.
    func isStale(at now: Date) -> Bool {
        windows.contains { ($0.resetsAt ?? .distantFuture) <= now }
    }
}

/// What the store shows for one provider. A failed check keeps the last good snapshot.
struct ProviderState: Sendable, Equatable {
    var snapshot: ProviderSnapshot?
    var error: String?
}

enum Bar {
    /// Ten-cell text bar, such as "█████░░░░░".
    static func text(percent: Double, cells: Int = 10) -> String {
        let filled = min(cells, max(0, Int((percent / 100 * Double(cells)).rounded(.down))))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: cells - filled)
    }
}
