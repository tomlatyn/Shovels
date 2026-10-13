//
//  Guides.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import SwiftUI

/// Setup steps shown in place of a provider's card until its first successful check.
struct ConnectGuide: Identifiable {
    let id: String
    let title: String
    let steps: [String]

    /// Where Shovels looks for each CLI, shown in every guide.
    private static let whereToInstall = "Shovels finds the CLI through your shell's PATH. If it's installed somewhere unusual, the message above says how to point Shovels at it."

    static let all: [ConnectGuide] = [
        ConnectGuide(
            id: "claudeCode",
            title: "CLAUDE CODE",
            steps: [
                "Install Claude Code, then run 'claude' in Terminal.",
                "Sign in when it asks. The login stays on this Mac.",
                whereToInstall,
            ]
        ),
        ConnectGuide(
            id: "codex",
            title: "CODEX",
            steps: [
                "Install the Codex CLI.",
                "Run 'codex login' in Terminal and sign in with the ChatGPT account you want to track.",
                whereToInstall,
            ]
        ),
        ConnectGuide(
            id: "antigravity",
            title: "ANTIGRAVITY",
            steps: [
                "Install the agy command line from Antigravity, run 'agy' in Terminal, and sign in.",
                "Run 'agy' in Terminal from ~/Library/Application Support/Shovels/antigravity-workspace. Choose Yes when it asks to trust the folder. Shovels never answers that question for you.",
                whereToInstall,
            ]
        ),
        ConnectGuide(
            id: "cursor",
            title: "CURSOR",
            steps: [
                "Install the Cursor agent command line, then run 'agent login' in Terminal and sign in.",
                "Run 'agent' in Terminal from ~/Library/Application Support/Shovels/cursor-workspace. Choose Trust when it asks. Shovels never answers that question for you.",
                whereToInstall,
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
            HStack(spacing: 6) {
                if let provider = ProviderID(rawValue: guide.id) {
                    Image(nsImage: ProviderGlyph.image(for: provider, pointSize: 14))
                        .foregroundStyle(Palette.accent(for: provider))
                }
                Text(guide.title)
                    .font(Retro.title(9))
                    .foregroundStyle(Palette.phosphor)
            }
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
