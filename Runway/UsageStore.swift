import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    /// The last good reading. Kept when a later check fails, so the numbers don't vanish.
    private(set) var snapshot: ProviderSnapshot?
    private(set) var usageError: String?
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

    func refresh() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let checkedAt = Date.now
        // The CLI call and the log scan both run off the main actor.
        do {
            snapshot = try await Task.detached { try ClaudeProvider.snapshot(now: checkedAt) }.value
            usageError = nil
        } catch {
            usageError = (error as? ClaudeUsageError)?.message ?? error.localizedDescription
        }
        now = .now
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    func refreshNow() {
        Task { await refresh() }
    }

    /// Updates the toggle straight away. A usage check isn't needed for this, and it takes several seconds.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    /// The session percentage, or nil when there's no reading or its window has reset.
    private var freshSessionPercent: Double? {
        guard let snapshot, !snapshot.isStale(at: now),
              let session = snapshot.windows.first(where: { $0.label == "5H" }) else {
            return nil
        }
        return session.usedPercent
    }

    /// Menu bar text: the session percentage, or "?" when there's no fresh reading.
    var menuBarText: String {
        freshSessionPercent.map { "\(Int($0))%" } ?? "?"
    }

    /// Tooltip for the menu bar item. Says why there's no number yet.
    var menuBarHelp: String {
        if freshSessionPercent != nil {
            return "Claude Code: session limit used"
        }
        if let usageError {
            return usageError
        }
        return "Checking Claude Code usage"
    }
}
