import SwiftUI

/// How-to text shown in the dashboard. Each guide is one row; tapping it shows the steps.
struct ConnectGuide: Identifiable {
    let id: String
    let title: String
    /// One word for the row, such as CONNECTED or SETUP.
    let badge: String
    let status: String
    let steps: [String]

    static let all: [ConnectGuide] = [
        ConnectGuide(
            id: "claudeCode",
            title: "CLAUDE CODE",
            badge: "CONNECTED",
            status: "Shows session, weekly, and five-hour tokens.",
            steps: [
                "Install Claude Code, then run 'claude' in Terminal.",
                "Sign in when it asks. The login stays on this Mac.",
                "Shovels runs 'claude -p /usage' every five minutes.",
            ]
        ),
        ConnectGuide(
            id: "codex",
            title: "CODEX",
            badge: "CONNECTED",
            status: "Reads limits through the Codex app server.",
            steps: [
                "Install the Codex CLI.",
                "Run 'codex login' in Terminal and sign in with the ChatGPT account you want to track.",
                "Shovels asks Codex for its rate limits every five minutes.",
            ]
        ),
        ConnectGuide(
            id: "antigravity",
            title: "ANTIGRAVITY",
            badge: "CONNECTED",
            status: "Reads the agy CLI's /usage screen.",
            steps: [
                "Install the agy command line from Antigravity.",
                "Run 'agy' in Terminal once and sign in when it asks.",
                "Shovels opens agy in the background to read /usage. Each check takes about 20 seconds.",
            ]
        ),
        ConnectGuide(
            id: "cursor",
            title: "CURSOR",
            badge: "SETUP",
            status: "Needs a one-time trust step.",
            steps: [
                "Install the Cursor agent command line.",
                "Run 'agent login' in Terminal and sign in.",
                "Run 'agent' in Terminal from ~/Library/Application Support/Shovels/cursor-workspace. Choose Trust when it asks. Shovels never answers that question for you.",
            ]
        ),
    ]
}

extension ConnectGuide {
    static func `for`(_ provider: ProviderID) -> ConnectGuide? {
        all.first { $0.id == provider.rawValue }
    }
}

/// Shown in place of a provider's card while that provider isn't connected yet.
struct GuideCard: View {
    let guide: ConnectGuide
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(guide.title)
                .font(Retro.title(9))
                .foregroundStyle(Palette.phosphor)
            if !message.isEmpty {
                Text(message)
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.alert)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)")
                    .font(Retro.body(17))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().stroke(Palette.border, lineWidth: 1))
    }
}
