import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    private(set) var snapshot: ProviderSnapshot?
    private(set) var setupStatus: ClaudeSetup.Status = .notConfigured
    private(set) var now: Date = .now
    private(set) var setupError: String?
    private(set) var launchAtLogin = false
    private(set) var loginError: String?
    private var timer: Timer?

    init() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        let now = Date.now
        // File reads and log scans run off the main actor.
        let snapshot = await Task.detached { ClaudeProvider.snapshot(now: now) }.value
        self.snapshot = snapshot
        self.now = now
        self.setupStatus = ClaudeSetup.status()
        self.launchAtLogin = LaunchAtLogin.isEnabled
    }

    func refreshNow() {
        Task { await refresh() }
    }

    func enableLimits() {
        do {
            try ClaudeSetup.enable()
            setupError = nil
        } catch {
            setupError = error.localizedDescription
        }
        refreshNow()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        refreshNow()
    }

    /// Monochrome menu bar text, such as "CC 47%" or "CC ?" when there's no fresh reading.
    var menuBarTitle: String {
        guard let snapshot, !snapshot.isStale(at: now),
              let fiveHour = snapshot.windows.first(where: { $0.label == "5H" }),
              let percent = fiveHour.usedPercent else {
            return "CC ?"
        }
        return "CC \(Int(percent))%"
    }
}
