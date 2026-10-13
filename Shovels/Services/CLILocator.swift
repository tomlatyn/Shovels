//
//  CLILocator.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation
import os

/// A CLI Shovels looked for and didn't find.
struct CLINotFound: ProviderFailure {
    let name: String
    let override: String?
    let searched: [String]
    var needsSetup: Bool { true }

    var errorDescription: String? {
        if let override {
            return "The path set for '\(name)' isn't a program: \(override). Fix it with: defaults write \(CLILocator.domain) \(CLILocator.overrideKey(name)) /path/to/\(name)"
        }
        let home = NSHomeDirectory()
        let list = searched.map { $0.replacingOccurrences(of: home, with: "~") }.joined(separator: ", ")
        return "Couldn't find '\(name)'. Looked in your shell's PATH and \(list). If it's somewhere else, run: defaults write \(CLILocator.domain) \(CLILocator.overrideKey(name)) /path/to/\(name)"
    }
}

/// Finds vendor CLIs the way Terminal would, and builds the environment they run with.
/// Apps opened from Finder don't get the shell's PATH, so the login shell is asked once and the answer kept.
enum CLILocator {
    static let domain = Bundle.main.bundleIdentifier ?? "com.tomaslatyn.shovels"

    /// Common install folders, checked after the shell's PATH.
    static var commonDirectories: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.claude/local",
            "\(home)/.npm-global/bin",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
        ]
    }

    private static let shellPathCache = OSAllocatedUnfairLock<[String]?>(initialState: nil)

    static func overrideKey(_ name: String) -> String { "cliPath.\(name)" }

    /// The CLI's full path: a path set with `defaults write`, then the shell's PATH, then common folders.
    static func locate(_ name: String) throws -> String {
        if let override = UserDefaults.standard.string(forKey: overrideKey(name)), !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            guard FileManager.default.isExecutableFile(atPath: expanded) else {
                throw CLINotFound(name: name, override: override, searched: [])
            }
            return expanded
        }
        let directories = unique(shellPath() + commonDirectories)
        for directory in directories {
            let candidate = (directory as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        throw CLINotFound(name: name, override: nil, searched: commonDirectories)
    }

    /// The app's environment, with a PATH that has the CLI's own folder first, then the shell's PATH.
    /// Many CLIs are node scripts and need `node` from the same place the shell finds it.
    static func environment(for executable: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let own = (executable as NSString).deletingLastPathComponent
        environment["PATH"] = unique([own] + shellPath() + commonDirectories + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
            .joined(separator: ":")
        return environment
    }

    /// Forgets the shell's PATH, so a CLI installed since the last check is found. Called on REFRESH.
    static func reset() {
        shellPathCache.withLock { $0 = nil }
    }

    /// PATH as the user's interactive login shell sets it. Empty if the shell fails or takes over 5 seconds.
    static func shellPath() -> [String] {
        if let cached = shellPathCache.withLock({ $0 }) { return cached }
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let marker = "__SHOVELS_PATH__"
        var found: [String] = []
        if let output = try? CommandRunner.run(
            path: shell,
            arguments: ["-ilc", "printf '\(marker)%s\(marker)' \"$PATH\""],
            directory: URL(fileURLWithPath: NSHomeDirectory()),
            timeout: 5,
            environment: ProcessInfo.processInfo.environment
        ), let start = output.stdout.range(of: marker),
           let end = output.stdout.range(of: marker, range: start.upperBound..<output.stdout.endIndex) {
            // Shell startup files can print anything, so only the text between the markers counts.
            found = output.stdout[start.upperBound..<end.lowerBound]
                .split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        }
        let result = found
        shellPathCache.withLock { $0 = result }
        return result
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}
