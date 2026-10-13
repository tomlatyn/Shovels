//
//  DashboardView.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import AppKit
import SwiftUI

struct DashboardView: View {
    let store: UsageStore
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(nsImage: ProviderGlyph.image(rows: ProviderGlyph.shovel))
                    Text("SHOVELS")
                        .font(Retro.title(12))
                }
                .foregroundStyle(Palette.phosphor)
                Spacer()
                Text(store.lastChecked.map { "Checked " + $0.formatted(.relative(presentation: .named)) } ?? "Checking…")
                    .font(Retro.body(18))
                    .foregroundStyle(Palette.secondary)
            }
            if showingSettings {
                settingsPanel
            } else {
                ForEach(store.visibleProviders, id: \.self) { provider in
                    if isUnconnected(store.state(for: provider)), let guide = ConnectGuide.for(provider) {
                        GuideCard(guide: guide, message: store.state(for: provider).error ?? "")
                    } else {
                        ProviderCard(provider: provider, state: store.state(for: provider), now: store.now, store: store,
                                     isMain: store.mainProvider == provider)
                    }
                }
                if store.visibleProviders.isEmpty {
                    Text("All providers are hidden. Turn one on below.")
                        .foregroundStyle(Palette.secondary)
                }
            }
            footer
        }
        .font(Retro.body(20))
        .padding(14)
        .frame(width: 372, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.panel)
        // Closing the window returns to the dashboard, not settings.
        .onDisappear { showingSettings = false }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !showingSettings {
                TerminalButton(title: store.isChecking ? "CHECKING" : "REFRESH") { store.refreshNow() }
            }
            Spacer()
            TerminalButton(title: showingSettings ? "BACK" : "SETTINGS") { showingSettings.toggle() }
            TerminalButton(title: "QUIT") { NSApplication.shared.terminate(nil) }
        }
    }

    /// Settings replace the cards while open, so the window never grows past the screen.
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SHOW")
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.secondary)
                ForEach(ProviderID.allCases, id: \.self) { provider in
                    let on = !store.hidden.contains(provider)
                    TerminalButton(title: "\(provider.displayName)  \(on ? "ON" : "OFF")", filled: on) {
                        store.toggleVisible(provider)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("MENU BAR SHOWS")
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.secondary)
                ForEach(ProviderID.allCases, id: \.self) { provider in
                    TerminalButton(title: provider.displayName, filled: store.mainProvider == provider) {
                        store.setMain(provider)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("ALERTS AT 80% AND 95%")
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.secondary)
                TerminalButton(title: store.alertsEnabled ? "ALERTS: ON" : "ALERTS: OFF") {
                    store.toggleAlerts()
                }
                TerminalButton(title: "TEST ALERT") { store.sendTestAlert() }
                if let note = store.alertNote {
                    Text(note)
                        .font(Retro.body(17))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("STARTUP")
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.secondary)
                TerminalButton(title: store.launchAtLogin ? "OPEN AT LOGIN: ON" : "OPEN AT LOGIN: OFF") {
                    store.setLaunchAtLogin(!store.launchAtLogin)
                }
                if let error = store.loginError {
                    Text(error)
                        .font(Retro.body(17))
                        .foregroundStyle(Palette.alert)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(Palette.border, lineWidth: 1))
    }
}

/// Not connected: no reading yet, and the problem is setup, not an outage.
func isUnconnected(_ state: ProviderState) -> Bool {
    state.snapshot == nil && state.error != nil && !state.outage
}

struct ProviderCard: View {
    let provider: ProviderID
    let state: ProviderState
    let now: Date
    let store: UsageStore
    var isMain = false

    private var snapshot: ProviderSnapshot? { state.snapshot }
    private var hasWindows: Bool { !(snapshot?.windows.isEmpty ?? true) }
    private var stale: Bool { snapshot?.isStale(at: now) ?? false }

    /// Stale cards drop their provider color, so old data doesn't look live.
    private var accent: Color {
        stale ? Palette.secondary : Palette.accent(for: provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(nsImage: ProviderGlyph.image(for: provider, pointSize: 14))
                    .foregroundStyle(accent)
                Text(provider.displayName)
                    .font(Retro.title(9))
                    .foregroundStyle(accent)
                Spacer()
                if isMain {
                    Text("MENU BAR")
                        .font(Retro.body(13))
                        .foregroundStyle(Palette.phosphor)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 0)
                        .overlay(Rectangle().stroke(Palette.phosphor, lineWidth: 1))
                }
                if let plan = snapshot?.plan {
                    Text(plan)
                        .foregroundStyle(Palette.secondary)
                }
            }

            if let snapshot, hasWindows {
                ForEach(snapshot.windows, id: \.title) { window in
                    WindowRow(window: window, accent: accent, now: now,
                              series: store.series(for: provider, window: window),
                              runway: store.runway(for: provider, window: window))
                }
            } else if let error = state.error {
                Text(error)
                    .font(state.outage ? Retro.body(17) : Retro.body(20))
                    .foregroundStyle(state.outage ? Palette.secondary : Palette.alert)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Checking usage…")
                    .foregroundStyle(Palette.secondary)
            }

            if let error = state.error, hasWindows {
                Text("Couldn't refresh: \(error)")
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.alert)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let tokens = snapshot?.tokensLast5h {
                Text("Tokens, last 5 hours: \(tokens.formatted(.number.notation(.compactName)))")
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().stroke(Palette.border, lineWidth: 1))
    }
}

struct TerminalButton: View {
    let title: String
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Retro.body(18))
                .fixedSize()
                .foregroundStyle(Palette.phosphor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(filled ? Color(hex: 0x22352A) : Color.clear)
                .overlay(Rectangle().stroke(Palette.phosphor, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct WindowRow: View {
    let window: UsageWindow
    let accent: Color
    let now: Date
    let series: [UsageSample]
    let runway: TimeInterval?

    /// Names that say how long the window is, so "Session" never has to mean three things.
    private var displayName: String {
        switch window.minutes {
        case 300: "5-hour"
        case 10080: "Weekly"
        case 43200: "Monthly"
        default: window.title
        }
    }

    /// A sparkline needs at least 10 minutes of readings. Two points look like noise.
    private var hasEnoughHistory: Bool {
        guard series.count >= 3, let first = series.first, let last = series.last else { return false }
        return last.at - first.at >= 600
    }

    /// Shown when the window would fill before it resets.
    private var runwayText: String? {
        guard let runway, percent != nil, let resetsAt = window.resetsAt else { return nil }
        guard runway < resetsAt.timeIntervalSince(now) else { return nil }
        return "At this pace: full in \(Formatting.duration(runway))"
    }

    private var expired: Bool { (window.resetsAt ?? .distantFuture) <= now }
    private var percent: Double? { expired ? nil : window.usedPercent }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Text(displayName)
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 80, alignment: .leading)
                CellBar(percent: percent, color: barColor)
                Spacer()
                Text(percentLabel)
                    .fixedSize()
                    .foregroundStyle(percent == nil ? Palette.secondary : Palette.phosphor)
            }
            Text(resetLabel)
                .font(Retro.body(17))
                .foregroundStyle(Palette.secondary)
                .padding(.leading, 90)
            if hasEnoughHistory {
                Sparkline(values: series.map(\.used), color: accent)
                    .padding(.leading, 90)
            }
            if let runwayText {
                Text(runwayText)
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.alert)
                    .padding(.leading, 90)
            }
        }
    }

    /// Red marks near-limit only. Old data is never red.
    private var barColor: Color {
        guard let percent else { return Palette.border }
        return percent >= 90 ? Palette.alert : accent
    }

    private var percentLabel: String {
        guard let percent else { return "reset" }
        return "\(Int(percent))%"
    }

    private var resetLabel: String {
        guard let resetsAt = window.resetsAt else { return "reset time unknown" }
        let remaining = resetsAt.timeIntervalSince(now)
        if remaining <= 0 { return "Reset. Checks again on refresh." }
        return "Resets in " + Formatting.duration(remaining)
    }

}

/// Ten pixel cells, filled to the percentage. Drawn as shapes, so the bar doesn't depend on a font.
struct CellBar: View {
    let percent: Double?
    let color: Color
    var cells = 20

    var body: some View {
        let filled = min(cells, max(0, Int(((percent ?? 0) / 100 * Double(cells)).rounded(.down))))
        HStack(spacing: 2) {
            ForEach(0..<cells, id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? color : Palette.border)
                    .frame(width: 7, height: 14)
            }
        }
    }
}
