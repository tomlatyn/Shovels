import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    /// Providers shown in the menu bar, in order.
    static let menuProviders: [ProviderID] = ProviderID.allCases

    private(set) var states: [ProviderID: ProviderState] = [:]
    private(set) var isChecking = false
    private(set) var now: Date = .now
    private(set) var launchAtLogin = false
    private(set) var loginError: String?
    private var timer: Timer?

    init() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func state(for provider: ProviderID) -> ProviderState {
        states[provider] ?? ProviderState()
    }

    /// Checks every provider at once. Each check runs off the main actor.
    func refresh() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let checkedAt = Date.now
        async let claudeFresh = Self.load(.claudeCode, at: checkedAt)
        async let codexFresh = Self.load(.codex, at: checkedAt)
        async let antigravityFresh = Self.load(.antigravity, at: checkedAt)
        async let cursorFresh = Self.load(.cursor, at: checkedAt)
        let fresh: [ProviderID: ProviderState] = [
            .claudeCode: await claudeFresh,
            .codex: await codexFresh,
            .antigravity: await antigravityFresh,
            .cursor: await cursorFresh,
        ]
        for (provider, result) in fresh {
            states[provider] = Self.merge(result, into: state(for: provider))
        }
        now = .now
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func refreshNow() {
        Task { await refresh() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    /// A failed check keeps the last good snapshot and records the error.
    private static func merge(_ fresh: ProviderState, into old: ProviderState) -> ProviderState {
        if fresh.snapshot != nil { return fresh }
        return ProviderState(snapshot: old.snapshot, error: fresh.error)
    }

    nonisolated private static func load(_ provider: ProviderID, at now: Date) async -> ProviderState {
        await Task.detached {
            do {
                let snapshot: ProviderSnapshot
                switch provider {
                case .claudeCode: snapshot = try ClaudeProvider.snapshot(now: now)
                case .codex: snapshot = try CodexUsage.snapshot(now: now)
                case .antigravity: snapshot = try AntigravityUsage.snapshot(now: now)
                case .cursor: snapshot = try CursorUsage.snapshot(now: now)
                }
                return ProviderState(snapshot: snapshot, error: nil)
            } catch {
                return ProviderState(snapshot: nil, error: message(for: error))
            }
        }.value
    }

    nonisolated private static func message(for error: Error) -> String {
        if let error = error as? ClaudeUsageError { return error.message }
        if let error = error as? CodexUsageError { return error.message }
        if let error = error as? AntigravityUsageError { return error.message }
        if let error = error as? CursorUsageError { return error.message }
        return error.localizedDescription
    }

    /// The first window's percentage, or nil when there's no fresh reading.
    func menuPercent(for provider: ProviderID) -> Double? {
        guard let snapshot = state(for: provider).snapshot, !snapshot.isStale(at: now),
              let window = snapshot.windows.first else {
            return nil
        }
        return window.usedPercent
    }

    /// Menu bar text for one provider: its percentage, or "?" when there's no fresh reading.
    func menuText(for provider: ProviderID) -> String {
        menuPercent(for: provider).map { "\(Int($0))%" } ?? "?"
    }

    /// Tooltip for the menu bar item. Says why there's no number yet.
    var menuBarHelp: String {
        ProviderID.allCases.map { provider in
            if menuPercent(for: provider) != nil {
                return "\(provider.displayName.capitalized): usage shown"
            }
            return state(for: provider).error ?? "\(provider.displayName.capitalized): checking usage"
        }
        .joined(separator: "\n")
    }
}
