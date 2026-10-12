import Foundation

/// Connects Runway to Claude Code by setting Claude Code's status line to Runway's helper.
/// Nothing changes until the user confirms in the dashboard, and Disconnect undoes it.
enum ClaudeSetup {
    enum Status: Sendable, Equatable {
        /// Runway isn't connected, and Claude Code has no status line set.
        case notConfigured
        /// Runway is connected. Usage appears after Claude's next reply.
        case installed
        /// Another tool owns Claude Code's status line. Runway won't replace it.
        case otherStatusLineSet
    }

    enum SetupError: LocalizedError {
        case unreadableSettings
        case statusLineInUse
        case notConnected

        var errorDescription: String? {
            switch self {
            case .unreadableSettings:
                "Runway couldn't read Claude Code's settings, so nothing was changed."
            case .statusLineInUse:
                "Claude Code already uses a status line from another tool, so Runway left it alone."
            case .notConnected:
                "Runway isn't connected to Claude Code."
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

    /// Saves a backup of Claude Code's settings, then sets Runway's helper as the status line.
    static func connect() throws {
        var settings = try readSettings() ?? [:]
        guard settings["statusLine"] == nil else { throw SetupError.statusLineInUse }

        try FileManager.default.createDirectory(at: RunwayPaths.support, withIntermediateDirectories: true)
        try helperScript.write(to: RunwayPaths.helperScript, atomically: true, encoding: .utf8)
        try backupSettings()

        settings["statusLine"] = ["type": "command", "command": helperCommand]
        try writeSettings(settings)
    }

    /// Removes Runway's status line and its saved limits. Leaves any other tool's status line alone.
    static func disconnect() throws {
        guard var settings = try readSettings(),
              let statusLine = settings["statusLine"] as? [String: Any],
              statusLine["command"] as? String == helperCommand else {
            throw SetupError.notConnected
        }

        try backupSettings()
        settings["statusLine"] = nil
        try writeSettings(settings)
        try? FileManager.default.removeItem(at: RunwayPaths.limitsFile)
    }

    private static func backupSettings() throws {
        guard FileManager.default.fileExists(atPath: RunwayPaths.claudeSettings.path) else { return }
        let backup = RunwayPaths.support.appending(path: "settings-backup.json")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.copyItem(at: RunwayPaths.claudeSettings, to: backup)
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
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
