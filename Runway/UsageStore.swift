import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    private(set) var snapshot: ProviderSnapshot?
    private(set) var setupStatus: ClaudeSetup.Status = .notConfigured
    private(set) var now: Date = .now
    private(set) var connectError: String?
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

    func connect() {
        do {
            try ClaudeSetup.connect()
            connectError = nil
        } catch {
            connectError = error.localizedDescription
        }
        refreshNow()
    }

    func disconnect() {
        do {
            try ClaudeSetup.disconnect()
            connectError = nil
        } catch {
            connectError = error.localizedDescription
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

    /// The 5-hour percentage, or nil when there's no fresh reading.
    private var freshFiveHourPercent: Double? {
        guard let snapshot, !snapshot.isStale(at: now),
              let fiveHour = snapshot.windows.first(where: { $0.label == "5H" }) else {
            return nil
        }
        return fiveHour.usedPercent
    }

    /// Menu bar text: the 5-hour percentage, or "?" when there's no fresh reading.
    var menuBarText: String {
        freshFiveHourPercent.map { "\(Int($0))%" } ?? "?"
    }

    /// Tooltip for the menu bar item. Says why there's no number yet.
    var menuBarHelp: String {
        if freshFiveHourPercent != nil {
            return "Claude Code: 5-hour limit used"
        }
        switch setupStatus {
        case .notConfigured:
            return "Connect Claude Code in Runway to see your limits"
        case .installed:
            return "Waiting for Claude Code's next reply"
        case .otherStatusLineSet:
            return "Claude Code's status line belongs to another tool"
        }
    }
}
