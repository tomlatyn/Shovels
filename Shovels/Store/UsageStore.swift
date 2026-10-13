//
//  UsageStore.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    private static let hiddenKey = "hiddenProviders"
    private static let mainKey = "mainProvider"
    private static let alertsKey = "alertsEnabled"

    private(set) var states: [ProviderID: ProviderState] = [:]
    /// Providers you've hidden from the dashboard and the menu bar.
    private(set) var hidden: Set<ProviderID>
    /// The provider whose percentage shows in the menu bar.
    private(set) var mainProvider: ProviderID
    private(set) var isChecking = false
    private(set) var lastChecked: Date?
    private(set) var now: Date = .now
    private(set) var launchAtLogin = false
    private(set) var alertsEnabled: Bool
    private(set) var loginError: String?
    private var timer: Timer?
    private var retryTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        hidden = Set((defaults.stringArray(forKey: Self.hiddenKey) ?? []).compactMap(ProviderID.init(rawValue:)))
        mainProvider = defaults.string(forKey: Self.mainKey).flatMap(ProviderID.init(rawValue:)) ?? .claudeCode
        alertsEnabled = defaults.object(forKey: Self.alertsKey) as? Bool ?? true
        Alerts.requestPermission()
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
        lastChecked = checkedAt
        if alertsEnabled {
            for provider in ProviderID.allCases {
                if let snapshot = states[provider]?.snapshot {
                    Alerts.check(snapshot, now: checkedAt)
                }
            }
        }
        launchAtLogin = LaunchAtLogin.isEnabled
        // A provider that was working and now fails is probably an outage. Retry in a minute.
        // Setup problems, such as a missing CLI or a trust prompt, don't retry on their own.
        if ProviderID.allCases.contains(where: { state(for: $0).error != nil && state(for: $0).snapshot != nil }) {
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Providers that are on, in display order.
    var visibleProviders: [ProviderID] {
        ProviderID.allCases.filter { !hidden.contains($0) }
    }

    /// The provider the menu bar shows: the main one, or the first visible one if the main one is hidden.
    var menuProvider: ProviderID? {
        hidden.contains(mainProvider) ? visibleProviders.first : mainProvider
    }

    func toggleVisible(_ provider: ProviderID) {
        if hidden.contains(provider) {
            hidden.remove(provider)
        } else {
            hidden.insert(provider)
        }
        UserDefaults.standard.set(hidden.map(\.rawValue).sorted(), forKey: Self.hiddenKey)
    }

    func toggleAlerts() {
        alertsEnabled.toggle()
        UserDefaults.standard.set(alertsEnabled, forKey: Self.alertsKey)
    }

    func sendTestAlert() {
        Alerts.post(title: "Shovels", body: "Test alert. Notifications are working.")
    }

    func setMain(_ provider: ProviderID) {
        mainProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: Self.mainKey)
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
        return ProviderState(snapshot: old.snapshot, error: fresh.error, outage: fresh.outage)
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
                return ProviderState(snapshot: nil, error: message(for: error), outage: isOutage(error))
            }
        }.value
    }

    nonisolated private static func isOutage(_ error: Error) -> Bool {
        if let error = error as? CursorUsageError, case .unavailable = error { return true }
        return false
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
        visibleProviders.map { provider in
            if menuPercent(for: provider) != nil {
                return "\(provider.displayName.capitalized): usage shown"
            }
            return state(for: provider).error ?? "\(provider.displayName.capitalized): checking usage"
        }
        .joined(separator: "\n")
    }
}
