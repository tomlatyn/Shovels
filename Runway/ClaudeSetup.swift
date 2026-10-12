import Foundation

/// Installs the status line helper that Runway reads limits from.
/// Nothing is written until the user confirms in the dashboard.
enum ClaudeSetup {
    enum Status: Sendable, Equatable {
        /// No status line is set, so Runway can offer to set its helper.
        case notConfigured
        /// Runway's helper is the status line. Limits appear after the next Claude response.
        case installed
        /// Another status line is set. Runway leaves it alone.
        case otherStatusLineSet
    }

    enum SetupError: LocalizedError {
        case unreadableSettings
        case statusLineInUse

        var errorDescription: String? {
            switch self {
            case .unreadableSettings: "Could not read ~/.claude/settings.json. Nothing was changed."
            case .statusLineInUse: "A status line is already set. Nothing was changed."
            }
        }
    }

    /// Runs through sh, so the path with a space in it works without extra quoting rules.
    static let helperCommand = "sh \"$HOME/Library/Application Support/Runway/claude-statusline.sh\""

    static let helperScript = """
    #!/bin/sh
    # Runway: keeps the latest Claude Code status line JSON for Runway to read.
    cat > "$HOME/Library/Application Support/Runway/claude-limits.json"
    echo ""

    """

    static func status() -> Status {
        guard let settings = try? readSettings(), let statusLine = settings["statusLine"] as? [String: Any] else {
            return .notConfigured
        }
        let command = statusLine["command"] as? String ?? ""
        return command == helperCommand ? .installed : .otherStatusLineSet
    }

    /// Backs up settings, writes the helper script, and sets the status line.
    static func enable() throws {
        var settings = try readSettings() ?? [:]
        guard settings["statusLine"] == nil else { throw SetupError.statusLineInUse }

        try FileManager.default.createDirectory(at: RunwayPaths.support, withIntermediateDirectories: true)
        try helperScript.write(to: RunwayPaths.helperScript, atomically: true, encoding: .utf8)

        if FileManager.default.fileExists(atPath: RunwayPaths.claudeSettings.path) {
            let backup = RunwayPaths.support.appending(path: "settings-backup.json")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: RunwayPaths.claudeSettings, to: backup)
        }

        settings["statusLine"] = ["type": "command", "command": helperCommand]
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(
            at: RunwayPaths.claudeSettings.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: RunwayPaths.claudeSettings, options: .atomic)
    }

    /// nil when the file doesn't exist. Throws when it exists but can't be parsed,
    /// so Runway never overwrites a file it couldn't read.
    private static func readSettings() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: RunwayPaths.claudeSettings.path) else { return nil }
        let data = try Data(contentsOf: RunwayPaths.claudeSettings)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SetupError.unreadableSettings
        }
        return object
    }
}
