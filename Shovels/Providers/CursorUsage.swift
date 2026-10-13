//
//  CursorUsage.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation

enum CursorUsageError: Error, Sendable {
    case notInstalled
    /// Cursor's usage service answered with an error. This is an outage on Cursor's side, not a setup problem.
    case unavailable
    case noUsage(String)

    var message: String {
        switch self {
        case .notInstalled:
            "Cursor's agent CLI isn't installed. Install it, then sign in with 'agent login' in Terminal."
        case .unavailable:
            "Cursor is down right now. Retrying automatically. Status: cursor.com/dashboard?tab=usage"
        case .noUsage(let detail):
            detail
        }
    }
}

/// Reads Cursor usage from the agent CLI's /usage screen, the same screen you see in Terminal.
/// Cursor asks you to trust a folder before it runs. Shovels never answers that question. You answer it once, in Terminal.
enum CursorUsage {
    static let candidatePaths = [
        "\(NSHomeDirectory())/.local/bin/agent",
        "/opt/homebrew/bin/agent",
        "/usr/local/bin/agent",
    ]

    /// Empty folder Shovels runs the agent in. You trust it once, in Terminal.
    static var workspace: URL {
        ShovelsPaths.support.appending(path: "cursor-workspace", directoryHint: .isDirectory)
    }

    static let trustMessage = "Cursor needs this folder trusted. Run 'agent' in Terminal from ~/Library/Application Support/Shovels/cursor-workspace, choose Trust, then refresh."

    static func snapshot(now: Date) throws -> ProviderSnapshot {
        guard let path = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw CursorUsageError.notInstalled
        }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        do {
            let screen = try TerminalSession.run(
                path: path,
                directory: workspace,
                command: "/usage",
                startupSeconds: 12,
                replySeconds: 8,
                blocked: { text in
                    text.contains("Trust this workspace") || text.contains("Workspace Trust Required") ? trustMessage : nil
                }
            )
            return try parse(screen, now: now)
        } catch TerminalSessionError.blockedByPrompt(let message) {
            throw CursorUsageError.noUsage(message)
        }
    }

    /// Parsed once a real /usage screen has been captured. Until then this reports that it isn't read yet.
    static func parse(_ screen: String, now: Date) throws -> ProviderSnapshot {
        if screen.contains("Failed to load usage data") {
            throw CursorUsageError.unavailable
        }
        throw CursorUsageError.noUsage("Cursor's usage screen came back in a format Shovels doesn't read yet.")
    }
}
