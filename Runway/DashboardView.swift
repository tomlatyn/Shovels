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
        .background(Palette.panel)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TerminalButton(title: "REFRESH") { store.refreshNow() }
                TerminalButton(title: store.launchAtLogin ? "LOGIN: ON" : "LOGIN: OFF") {
                    store.setLaunchAtLogin(!store.launchAtLogin)
                }
                Spacer()
                TerminalButton(title: "QUIT") { NSApplication.shared.terminate(nil) }
            }
            if let error = store.loginError {
                Text(error)
                    .font(Retro.body(16))
                    .foregroundStyle(Palette.alert)
            }
        }
    }
}

struct ClaudeCard: View {
    let store: UsageStore
    @State private var previewingSetup = false

    private var snapshot: ProviderSnapshot? { store.snapshot }
    private var hasLimits: Bool { !(snapshot?.windows.isEmpty ?? true) }
    private var stale: Bool { snapshot?.isStale(at: store.now) ?? false }

    /// Stale cards drop their provider color, so old data doesn't look live.
    private var accent: Color {
        stale ? Palette.secondary : Palette.accent(for: .claudeCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ProviderID.claudeCode.displayName)
                .font(Retro.title(9))
                .foregroundStyle(accent)

            if let snapshot, hasLimits {
                ForEach(snapshot.windows, id: \.label) { window in
                    WindowRow(window: window, accent: accent, now: store.now)
                }
                if let asOf = snapshot.asOf {
                    Text("src statusline · as of \(asOf.formatted(.relative(presentation: .named)))")
                        .font(Retro.body(17))
                        .foregroundStyle(Palette.secondary)
                }
            } else {
                setupBlock
            }

            if let tokens = snapshot?.tokensLast5h {
                Text("5H tokens in+out \(tokens.formatted(.number.notation(.compactName)))")
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .padding(10)
        .overlay(Rectangle().stroke(Palette.border, lineWidth: 1))
    }

    @ViewBuilder private var setupBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch store.setupStatus {
            case .notConfigured:
                Text("limits unavailable")
                    .foregroundStyle(Palette.secondary)
                if previewingSetup {
                    Text("Runway will set this in ~/.claude/settings.json. Your current file is backed up first.")
                        .font(Retro.body(17))
                        .foregroundStyle(Palette.secondary)
                    Text(ClaudeSetup.helperCommand)
                        .font(Retro.body(15))
                        .foregroundStyle(Palette.phosphor)
                    HStack(spacing: 8) {
                        TerminalButton(title: "WRITE SETTINGS") {
                            store.enableLimits()
                            previewingSetup = false
                        }
                        TerminalButton(title: "CANCEL") { previewingSetup = false }
                    }
                } else {
                    TerminalButton(title: "ENABLE LIMITS") { previewingSetup = true }
                }
                if let error = store.setupError {
                    Text(error)
                        .font(Retro.body(17))
                        .foregroundStyle(Palette.alert)
                }
            case .installed:
                Text("waiting for the first Claude response")
                    .foregroundStyle(Palette.secondary)
            case .otherStatusLineSet:
                Text("you already have a status line, so Runway leaves it alone")
                    .foregroundStyle(Palette.secondary)
            }
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
                Text(window.label)
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 28, alignment: .leading)
                Text(Bar.text(percent: percent ?? 0))
                    .foregroundStyle(barColor)
                Spacer()
                Text(percentLabel)
                    .foregroundStyle(percent == nil ? Palette.secondary : Palette.phosphor)
            }
            Text(resetLabel)
                .font(Retro.body(17))
                .foregroundStyle(Palette.secondary)
                .padding(.leading, 38)
        }
    }

    /// Red marks near-limit only. Old data is never red.
    private var barColor: Color {
        guard let percent else { return Palette.border }
        return percent >= 90 ? Palette.alert : accent
    }

    private var percentLabel: String {
        guard let percent else { return "RESET" }
        return "\(Int(percent))%"
    }

    private var resetLabel: String {
        guard let resetsAt = window.resetsAt else { return "reset time unknown" }
        if resetsAt <= now { return "window reset, waiting for next response" }
        return "resets " + resetsAt.formatted(.relative(presentation: .named))
    }
}
