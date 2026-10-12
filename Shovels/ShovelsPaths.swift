import Foundation

enum ShovelsPaths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var claudeProjects: URL { home.appending(path: ".claude/projects", directoryHint: .isDirectory) }
}
