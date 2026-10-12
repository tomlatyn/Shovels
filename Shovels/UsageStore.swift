import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    /// Providers shown in the menu bar, in order.
    static let menuProviders: [ProviderID] = [.claudeCode, .codex]

    private(set) var claude = ProviderState()
    private(set) var codex = ProviderState()
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
        switch provider {
        case .claudeCode: claude
        case .codex: codex
        }
    }

    /// Checks every provider at once. Each check runs off the main actor.
    func refresh() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let checkedAt = Date.now
        async let claudeFresh = Self.loadClaude(at: checkedAt)
        async let codexFresh = Self.loadCodex(at: checkedAt)
        claude = Self.merge(await claudeFresh, into: claude)
        codex = Self.merge(await codexFresh, into: codex)
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

    nonisolated private static func loadClaude(at now: Date) async -> ProviderState {
        await Task.detached {
            do {
                return ProviderState(snapshot: try ClaudeProvider.snapshot(now: now), error: nil)
            } catch {
                return ProviderState(snapshot: nil, error: (error as? ClaudeUsageError)?.message ?? error.localizedDescription)
            }
        }.value
    }

    nonisolated private static func loadCodex(at now: Date) async -> ProviderState {
        await Task.detached {
            do {
                return ProviderState(snapshot: try CodexUsage.snapshot(now: now), error: nil)
            } catch {
                return ProviderState(snapshot: nil, error: (error as? CodexUsageError)?.message ?? error.localizedDescription)
            }
        }.value
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
            let state = state(for: provider)
            if menuPercent(for: provider) != nil {
                return "\(provider.displayName.capitalized): usage shown"
            }
            return state.error ?? "\(provider.displayName.capitalized): checking usage"
        }
        .joined(separator: "\n")
    }
}
