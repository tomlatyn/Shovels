//
//  ShovelsPaths.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation

enum ShovelsPaths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    /// Shovels' own folder under Application Support.
    static var support: URL {
        home.appending(path: "Library/Application Support/Shovels", directoryHint: .isDirectory)
    }

    static var claudeProjects: URL { home.appending(path: ".claude/projects", directoryHint: .isDirectory) }
}
