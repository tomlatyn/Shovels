//
//  UsageStore.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import AppKit
import Foundation
import Observation
import os

@MainActor
@Observable
final class UsageStore {
    private static let hiddenKey = "hiddenProviders"
    private static let mainKey = "mainProvider"
    private static let alertsKey = "alertsEnabled"
    /// Regular check interval.
    private static let interval: TimeInterval = 300
    /// Waits before retrying a provider whose check failed for a reason that clears up on its own.
    /// After the last one, the regular check takes over.
    private static let retryDelays: [TimeInterval] = [60, 120, 240]
    /// A provider check that takes longer than this is abandoned, so one stuck CLI can't hold up the others.
    nonisolated private static let checkDeadline: TimeInterval = 90

    private(set) var states: [ProviderID: ProviderState] = [:]
    /// Providers you've hidden from the dashboard and the menu bar. Hidden providers aren't checked.
    private(set) var hidden: Set<ProviderID>
    /// The provider whose percentage shows in the menu bar.
    private(set) var mainProvider: ProviderID
    /// Providers with a check in progress.
    private(set) var checking: Set<ProviderID> = []
    private(set) var lastChecked: Date?
    /// The clock the views use. Ticks every 30 seconds, so countdowns and stale states stay current.
    private(set) var now: Date = .now
    private(set) var launchAtLogin = false
    private(set) var alertsEnabled: Bool
    private(set) var alertNote: String?
    private(set) var history: [UsageSample]
    private(set) var loginError: String?
    private var timers: [Timer] = []
    private var retryTasks: [ProviderID: Task<Void, Never>] = [:]
    private var failures: [ProviderID: Int] = [:]

    var isChecking: Bool { !checking.isEmpty }

    init() {
        let defaults = UserDefaults.standard
        hidden = Set((defaults.stringArray(forKey: Self.hiddenKey) ?? []).compactMap(ProviderID.init(rawValue:)))
        mainProvider = defaults.string(forKey: Self.mainKey).flatMap(ProviderID.init(rawValue:)) ?? .claudeCode
        alertsEnabled = defaults.object(forKey: Self.alertsKey) as? Bool ?? true
        history = UsageHistory.load()
        launchAtLogin = LaunchAtLogin.isEnabled
        Alerts.requestPermission()
        Task { await refresh() }

        schedule(every: Self.interval) { store in Task { await store.refresh() } }
        schedule(every: 30) { store in store.now = .now }
        // After sleep the readings are old. Wait a moment for the network, then check.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                await self?.refresh()
            }
        }
    }

    /// Timers run in common modes, so they keep firing while the dashboard window is open.
    private func schedule(every seconds: TimeInterval, _ action: @escaping @MainActor (UsageStore) -> Void) {
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                action(self)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    func state(for provider: ProviderID) -> ProviderState {
        states[provider] ?? ProviderState()
    }

    /// Checks the given providers, or every visible one. Each provider updates as soon as its own check ends,
    /// and a provider already being checked is skipped.
    func refresh(_ providers: [ProviderID]? = nil) async {
        let targets = (providers ?? visibleProviders).filter { !checking.contains($0) }
        guard !targets.isEmpty else { return }
        checking.formUnion(targets)
        let checkedAt = Date.now
        await withTaskGroup(of: (ProviderID, ProviderState).self) { group in
            for provider in targets {
                group.addTask { (provider, await Self.load(provider, at: checkedAt)) }
            }
            for await (provider, fresh) in group {
                finish(provider, fresh, checkedAt: checkedAt)
            }
        }
    }

    private func finish(_ provider: ProviderID, _ fresh: ProviderState, checkedAt: Date) {
        checking.remove(provider)
        states[provider] = Self.merge(fresh, into: state(for: provider))
        now = .now
        lastChecked = .now
        launchAtLogin = LaunchAtLogin.isEnabled

        if let snapshot = fresh.snapshot {
            failures[provider] = nil
            retryTasks[provider]?.cancel()
            retryTasks[provider] = nil
            // Only fresh readings go into history and alerts. A failed check keeps an old snapshot, which would repeat it.
            let resetEvents = UsageHistory.record([snapshot], now: checkedAt, into: &history)
            if alertsEnabled {
                Alerts.check(snapshot, now: checkedAt, history: history)
                resetEvents.forEach(Alerts.reset)
            }
        } else if !fresh.needsSetup {
            // Timeouts and outages usually clear up. Setup problems, such as a missing CLI or a trust prompt,
            // wait for the regular check or REFRESH.
            scheduleRetry(provider)
        }
    }

    private func scheduleRetry(_ provider: ProviderID) {
        let attempt = failures[provider, default: 0]
        guard attempt < Self.retryDelays.count else { return }
        failures[provider] = attempt + 1
        retryTasks[provider]?.cancel()
        retryTasks[provider] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.retryDelays[attempt]))
            guard !Task.isCancelled else { return }
            await self?.refresh([provider])
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
            Task { await refresh([provider]) }
        } else {
            hidden.insert(provider)
            retryTasks[provider]?.cancel()
            retryTasks[provider] = nil
        }
        UserDefaults.standard.set(hidden.map(\.rawValue).sorted(), forKey: Self.hiddenKey)
    }

    func toggleAlerts() {
        alertsEnabled.toggle()
        UserDefaults.standard.set(alertsEnabled, forKey: Self.alertsKey)
    }

    func sendTestAlert() {
        Task { alertNote = await Alerts.test() }
    }

    /// Samples for one window's current cycle, for its runway estimate.
    func series(for provider: ProviderID, window: UsageWindow) -> [UsageSample] {
        guard let resets = window.resetsAt else { return [] }
        return UsageHistory.series(history, provider: provider, window: window.key, resetsAt: resets)
    }

    /// Estimated time until the window is full at its recent pace.
    func runway(for provider: ProviderID, window: UsageWindow) -> TimeInterval? {
        UsageHistory.runway(series(for: provider, window: window), window: window, now: now)
    }

    func setMain(_ provider: ProviderID) {
        mainProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: Self.mainKey)
    }

    /// REFRESH: looks for the CLIs again, in case one was just installed, and checks every visible provider.
    func refreshNow() {
        CLILocator.reset()
        Task { await refresh() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        if enabled && LaunchAtLogin.needsApproval {
            loginError = "macOS needs your approval. Turn Shovels on in System Settings › General › Login Items."
            LaunchAtLogin.openSettings()
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    /// A failed check keeps the last good snapshot and records the error.
    private static func merge(_ fresh: ProviderState, into old: ProviderState) -> ProviderState {
        if fresh.snapshot != nil { return fresh }
        return ProviderState(snapshot: old.snapshot, error: fresh.error, needsSetup: fresh.needsSetup)
    }

    nonisolated private static func load(_ provider: ProviderID, at now: Date) async -> ProviderState {
        let late = ProviderState(
            snapshot: nil,
            error: "\(provider.displayName.capitalized) didn't finish checking in \(Int(checkDeadline)) seconds. Shovels will try again.",
            needsSetup: false
        )
        return await Blocking.run(timeout: checkDeadline, fallback: late) {
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
                return ProviderState(
                    snapshot: nil,
                    error: error.localizedDescription,
                    needsSetup: (error as? any ProviderFailure)?.needsSetup ?? false
                )
            }
        }
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

/// Runs blocking work on its own thread instead of Swift's shared pool, with a deadline.
/// If the work is still running at the deadline, the caller gets `fallback` and moves on.
enum Blocking {
    static func run<T: Sendable>(timeout: TimeInterval, fallback: T, _ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (T) -> Void = { value in
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(returning: value) }
            }
            Thread.detachNewThread { finish(work()) }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(fallback) }
        }
    }
}
