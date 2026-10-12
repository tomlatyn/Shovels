import AppKit
import SwiftUI

struct DashboardView: View {
    let store: UsageStore
    @State private var showingGuides = false

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
                Text(store.now, format: .dateTime.hour().minute())
                    .font(Retro.body(18))
                    .foregroundStyle(Palette.secondary)
            }
            ForEach(ProviderID.allCases, id: \.self) { provider in
                ProviderCard(provider: provider, state: store.state(for: provider), now: store.now)
            }
            if showingGuides {
                GuidesView()
            }
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
                TerminalButton(title: showingGuides ? "HIDE GUIDES" : "GUIDES") { showingGuides.toggle() }
                Spacer()
                TerminalButton(title: "QUIT") { NSApplication.shared.terminate(nil) }
            }
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
}

struct ProviderCard: View {
    let provider: ProviderID
    let state: ProviderState
    let now: Date

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
                Text(provider.displayName)
                    .font(Retro.title(9))
                    .foregroundStyle(accent)
                Spacer()
                if let plan = snapshot?.plan {
                    Text(plan)
                        .foregroundStyle(Palette.secondary)
                }
            }

            if let snapshot, hasWindows {
                ForEach(snapshot.windows, id: \.title) { window in
                    WindowRow(window: window, accent: accent, now: now)
                }
            } else if let error = state.error {
                Text(error)
                    .foregroundStyle(Palette.alert)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Checking usage…")
                    .foregroundStyle(Palette.secondary)
            }

            if let asOf = snapshot?.asOf {
                Text("Checked \(asOf.formatted(.relative(presentation: .named)))")
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.secondary)
            }

            if let error = state.error, hasWindows {
                Text("Couldn't refresh: \(error)")
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
                .fixedSize()
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
                Text(window.title)
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 80, alignment: .leading)
                CellBar(percent: percent, color: barColor)
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

/// Ten pixel cells, filled to the percentage. Drawn as shapes, so the bar doesn't depend on a font.
struct CellBar: View {
    let percent: Double?
    let color: Color
    var cells = 10

    var body: some View {
        let filled = min(cells, max(0, Int(((percent ?? 0) / 100 * Double(cells)).rounded(.down))))
        HStack(spacing: 2) {
            ForEach(0..<cells, id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? color : Palette.border)
                    .frame(width: 9, height: 14)
            }
        }
    }
}
