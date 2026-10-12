import AppKit
import SwiftUI

struct DashboardView: View {
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RUNWAY")
                    .font(Retro.title(12))
                    .foregroundStyle(Palette.phosphor)
                Spacer()
                Text(store.now, format: .dateTime.hour().minute())
                    .font(Retro.body(18))
                    .foregroundStyle(Palette.secondary)
            }
            ClaudeCard(store: store)
            footer
        }
        .font(Retro.body(20))
        .padding(14)
        .frame(width: 372, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.panel)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TerminalButton(title: store.isChecking ? "CHECKING" : "REFRESH") { store.refreshNow() }
                TerminalButton(title: store.launchAtLogin ? "OPEN AT LOGIN: ON" : "OPEN AT LOGIN: OFF") {
                    store.setLaunchAtLogin(!store.launchAtLogin)
                }
                Spacer()
                TerminalButton(title: "QUIT") { NSApplication.shared.terminate(nil) }
            }
            if let error = store.loginError {
                Text(error)
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.alert)
            }
        }
    }
}

struct ClaudeCard: View {
    let store: UsageStore

    private var snapshot: ProviderSnapshot? { store.snapshot }
    private var hasWindows: Bool { !(snapshot?.windows.isEmpty ?? true) }
    private var stale: Bool { snapshot?.isStale(at: store.now) ?? false }

    /// Stale cards drop their provider color, so old data doesn't look live.
    private var accent: Color {
        stale ? Palette.secondary : Palette.accent(for: .claudeCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ProviderID.claudeCode.displayName)
                .font(Retro.title(9))
                .foregroundStyle(accent)

            if let snapshot, hasWindows {
                ForEach(snapshot.windows, id: \.label) { window in
                    WindowRow(window: window, accent: accent, now: store.now)
                }
            } else if let usageError = store.usageError {
                Text(usageError)
                    .foregroundStyle(Palette.alert)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Checking Claude Code usage…")
                    .foregroundStyle(Palette.secondary)
            }

            if let asOf = snapshot?.asOf {
                Text("Checked \(asOf.formatted(.relative(presentation: .named)))")
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.secondary)
            }

            if let usageError = store.usageError, hasWindows {
                Text("Couldn't refresh: \(usageError)")
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.alert)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let tokens = snapshot?.tokensLast5h {
                Text("Last 5 hours: \(tokens.formatted(.number.notation(.compactName))) tokens")
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Retro.body(18))
                .foregroundStyle(Palette.phosphor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .overlay(Rectangle().stroke(Palette.phosphor, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct WindowRow: View {
    let window: UsageWindow
    let accent: Color
    let now: Date

    private var expired: Bool { (window.resetsAt ?? .distantFuture) <= now }
    private var percent: Double? { expired ? nil : window.usedPercent }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Text(windowName)
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 80, alignment: .leading)
                Text(Bar.text(percent: percent ?? 0))
                    .foregroundStyle(barColor)
                Spacer()
                Text(percentLabel)
                    .foregroundStyle(percent == nil ? Palette.secondary : Palette.phosphor)
            }
            Text(resetLabel)
                .font(Retro.body(17))
                .foregroundStyle(Palette.secondary)
                .padding(.leading, 90)
        }
    }

    /// Same names as Claude Code's /usage panel.
    private var windowName: String {
        switch window.label {
        case "5H": "Session"
        case "WK": "Weekly"
        default: window.label
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
        if resetsAt <= now { return "Reset. Checks again on refresh." }
        return "Resets " + resetsAt.formatted(.relative(presentation: .named))
    }
}
