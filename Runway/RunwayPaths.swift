import Foundation

enum RunwayPaths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Runway's own folder. Holds the helper script and the limits it writes.
    static var support: URL {
        home.appending(path: "Library/Application Support/Runway", directoryHint: .isDirectory)
    }

    static var limitsFile: URL { support.appending(path: "claude-limits.json") }
    static var helperScript: URL { support.appending(path: "claude-statusline.sh") }
    static var claudeSettings: URL { home.appending(path: ".claude/settings.json") }
    static var claudeProjects: URL { home.appending(path: ".claude/projects", directoryHint: .isDirectory) }
}
