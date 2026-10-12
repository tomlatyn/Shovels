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
                TerminalButton(title: "REFRESH") { store.refreshNow() }
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
    @State private var confirmingConnect: Bool

    init(store: UsageStore, startConfirming: Bool = false) {
        self.store = store
        _confirmingConnect = State(initialValue: startConfirming)
    }

    private var snapshot: ProviderSnapshot? { store.snapshot }
    private var hasLimits: Bool { !(snapshot?.windows.isEmpty ?? true) }
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

            if let snapshot, hasLimits {
                ForEach(snapshot.windows, id: \.label) { window in
                    WindowRow(window: window, accent: accent, now: store.now)
                }
                if let asOf = snapshot.asOf {
                    Text("Updated \(asOf.formatted(.relative(presentation: .named)))")
                        .font(Retro.body(17))
                        .foregroundStyle(Palette.secondary)
                }
            } else {
                statusMessage
            }

            if let tokens = snapshot?.tokensLast5h {
                Text("Last 5 hours: \(tokens.formatted(.number.notation(.compactName))) tokens")
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.secondary)
            }

            if store.setupStatus == .installed {
                TerminalButton(title: "DISCONNECT") { store.disconnect() }
            }

            if let error = store.connectError {
                Text(error)
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.alert)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().stroke(Palette.border, lineWidth: 1))
    }

    @ViewBuilder private var statusMessage: some View {
        switch store.setupStatus {
        case .notConfigured:
            if confirmingConnect {
                Text("Runway adds one line to Claude Code's settings. Your settings are backed up first. You can disconnect anytime.")
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.phosphor)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    TerminalButton(title: "CONNECT") {
                        store.connect()
                        confirmingConnect = false
                    }
                    TerminalButton(title: "NOT NOW") { confirmingConnect = false }
                }
            } else {
                Text("Not connected")
                    .foregroundStyle(Palette.phosphor)
                Text("Connect to see your usage here.")
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TerminalButton(title: "CONNECT CLAUDE CODE") { confirmingConnect = true }
            }
        case .installed:
            Text("Connected")
                .foregroundStyle(Palette.phosphor)
            Text("Usage appears after Claude's next reply.")
                .font(Retro.body(17))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .otherStatusLineSet:
            Text("Claude Code already uses a status line from another tool. Runway can't connect without replacing it.")
                .font(Retro.body(17))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                    .frame(width: 60, alignment: .leading)
                Text(Bar.text(percent: percent ?? 0))
                    .foregroundStyle(barColor)
                Spacer()
                Text(percentLabel)
                    .foregroundStyle(percent == nil ? Palette.secondary : Palette.phosphor)
            }
            Text(resetLabel)
                .font(Retro.body(17))
                .foregroundStyle(Palette.secondary)
                .padding(.leading, 70)
        }
    }

    private var windowName: String {
        switch window.label {
        case "5H": "5 hours"
        case "WK": "Week"
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
        if resetsAt <= now { return "Reset. Updates after your next reply." }
        return "Resets " + resetsAt.formatted(.relative(presentation: .named))
    }
}
