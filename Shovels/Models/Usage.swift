//
//  Usage.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

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
    /// The quota group the window belongs to, when a provider has more than one, such as Antigravity's
    /// "GEMINI" and "CLAUDE AND GPT". nil for providers with a single set of windows.
    var group: String? = nil
    /// Length of the window in minutes. 300 is the 5-hour session window.
    var minutes: Int
    /// nil when the source doesn't report a percentage.
    var usedPercent: Double?
    var resetsAt: Date?

    /// Identifies the window within its provider, for history, alerts, and list identity.
    var key: String {
        group.map { "\($0) \(title)" } ?? title
    }
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

/// An error from a provider check. `needsSetup` separates problems you must fix, such as a missing CLI
/// or a sign-in, from ones that clear up on their own, such as a timeout or an outage.
protocol ProviderFailure: LocalizedError, Sendable {
    var needsSetup: Bool { get }
}

/// What the store shows for one provider. A failed check keeps the last good snapshot.
struct ProviderState: Sendable, Equatable {
    var snapshot: ProviderSnapshot?
    var error: String?
    /// True when the error is a setup problem. False for timeouts and outages, which are shown in a calmer style.
    var needsSetup: Bool = false
}
