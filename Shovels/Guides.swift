import SwiftUI

/// How-to text shown in the dashboard: what is connected and what to run to connect the rest.
struct ConnectGuide: Identifiable {
    let id: String
    let title: String
    let status: String
    let steps: [String]

    static let all: [ConnectGuide] = [
        ConnectGuide(
            id: "claude",
            title: "CLAUDE CODE",
            status: "Connected. Shows session, weekly, and five-hour tokens.",
            steps: [
                "Install Claude Code, then run 'claude' in Terminal.",
                "Sign in when it asks. The login stays on this Mac.",
                "Shovels runs 'claude -p /usage' every five minutes. Nothing else is needed.",
            ]
        ),
        ConnectGuide(
            id: "codex",
            title: "CODEX",
            status: "Connected through the Codex app server.",
            steps: [
                "Install the Codex CLI.",
                "Run 'codex login' in Terminal and sign in with the ChatGPT account you want to track.",
                "Shovels asks Codex for its rate limits every five minutes.",
            ]
        ),
        ConnectGuide(
            id: "antigravity",
            title: "ANTIGRAVITY",
            status: "Connected through the agy CLI's /usage screen. Shovels checks it every five minutes.",
            steps: [
                "Install the agy command line from Antigravity.",
                "Run 'agy' in Terminal once and sign in when it asks.",
                "Shovels opens agy in the background to read /usage. Each check takes about 20 seconds.",
            ]
        ),
        ConnectGuide(
            id: "cursor",
            title: "CURSOR",
            status: "Needs a one-time trust step. Shovels reads usage from the agent CLI's /usage screen.",
            steps: [
                "Install the Cursor agent command line.",
                "Run 'agent login' in Terminal and sign in.",
                "Run 'agent' in Terminal from ~/Library/Application Support/Shovels/cursor-workspace. Choose Trust when it asks. Shovels never answers that question for you.",
            ]
        ),
    ]
}

struct GuidesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ConnectGuide.all) { guide in
                VStack(alignment: .leading, spacing: 4) {
                    Text(guide.title)
                        .font(Retro.title(9))
                        .foregroundStyle(Palette.phosphor)
                    Text(guide.status)
                        .font(Retro.body(17))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                            .font(Retro.body(18))
                            .foregroundStyle(Palette.phosphor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().stroke(Palette.border, lineWidth: 1))
            }
        }
    }
}
