import Foundation

enum RunwayPaths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var claudeProjects: URL { home.appending(path: ".claude/projects", directoryHint: .isDirectory) }
}
