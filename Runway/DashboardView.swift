import SwiftUI

struct DashboardView: View {
    let snapshots: [ProviderSnapshot]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RUNWAY")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.phosphor)
                Spacer()
                Text(now, format: .dateTime.hour().minute())
                    .foregroundStyle(Palette.secondary)
            }
            ForEach(snapshots, id: \.provider) { snapshot in
                ProviderCard(snapshot: snapshot, now: now)
            }
        }
        .font(.system(size: 13, design: .monospaced))
        .padding(14)
        .frame(width: 372, alignment: .leading)
        .background(Palette.panel)
    }
}

struct ProviderCard: View {
    let snapshot: ProviderSnapshot
    let now: Date

    private var stale: Bool { snapshot.isStale(at: now) }

    /// Stale cards drop their provider color, so old data doesn't look live.
    private var accent: Color {
        stale ? Palette.secondary : Palette.accent(for: snapshot.provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.provider.displayName)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                Spacer()
                Text(snapshot.plan ?? "")
                    .foregroundStyle(Palette.secondary)
            }
            ForEach(snapshot.windows, id: \.label) { window in
                WindowRow(window: window, accent: accent, now: now)
            }
            Text("src \(sourceName) · as of \(snapshot.asOf.formatted(.relative(presentation: .named)))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.secondary)
        }
        .padding(10)
        .overlay(Rectangle().stroke(Palette.border, lineWidth: 1))
    }

    private var sourceName: String {
        switch snapshot.source {
        case .localFile: "local file"
        case .statusLineHelper: "statusline"
        }
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
                .font(.system(size: 11, design: .monospaced))
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
        if resetsAt <= now { return "window reset, waiting for next run" }
        return "resets " + resetsAt.formatted(.relative(presentation: .named))
    }
}
