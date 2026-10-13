//
//  TerminalSession.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Darwin
import Foundation

enum TerminalSessionError: Error, Sendable {
    case couldNotStart
    /// The CLI stopped at a prompt Shovels must not answer, such as a workspace trust dialog.
    case blockedByPrompt(String)

    var message: String {
        switch self {
        case .couldNotStart: "Couldn't open a terminal session for the CLI."
        case .blockedByPrompt(let text): text
        }
    }
}

/// Runs an interactive CLI inside a pseudo-terminal, types a command, and returns the screen text.
/// The CLI sees a real terminal, so commands like /usage work the same as they do in Terminal.
enum TerminalSession {
    /// Starts the CLI, waits for it to draw, types `command` one key at a time, and reads the reply.
    /// `blocked` looks at the screen after startup. If it returns a message, nothing is typed.
    static func run(
        path: String,
        directory: URL,
        command: String,
        startupSeconds: Double,
        replySeconds: Double,
        blocked: (String) -> String?,
        replyUntil: ((String) -> Bool)? = nil
    ) throws -> String {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0,
              let namePointer = ptsname(master) else {
            throw TerminalSessionError.couldNotStart
        }
        let slave = open(String(cString: namePointer), O_RDWR | O_NOCTTY)
        guard slave >= 0 else {
            close(master)
            throw TerminalSessionError.couldNotStart
        }
        // TIOCSWINSZ, so the CLI lays out its screen at a readable width.
        var size = winsize(ws_row: 50, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, 0x8008_7467, &size)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        let terminal = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardInput = terminal
        process.standardOutput = terminal
        process.standardError = terminal
        do {
            try process.run()
        } catch {
            close(slave)
            close(master)
            throw TerminalSessionError.couldNotStart
        }
        close(slave)

        defer {
            if process.isRunning { process.terminate() }
            close(master)
        }

        var screen = Data()
        pump(master, for: startupSeconds, into: &screen)
        let startText = clean(screen)
        if let message = blocked(startText) {
            send(master, Array("\u{3}".utf8))
            throw TerminalSessionError.blockedByPrompt(message)
        }

        for byte in command.utf8 {
            send(master, [byte])
            pump(master, for: 0.1, into: &screen)
        }
        pump(master, for: 1.0, into: &screen)
        send(master, [0x0D])
        if let replyUntil {
            // Stop as soon as the reply is on screen, or after replySeconds.
            let deadline = Date().addingTimeInterval(replySeconds)
            while Date() < deadline && !replyUntil(clean(screen)) {
                pump(master, for: 0.5, into: &screen)
            }
        } else {
            pump(master, for: replySeconds, into: &screen)
        }

        // Ctrl-C closes the panel and the CLI. Then make sure it's gone.
        send(master, [0x03])
        pump(master, for: 1.0, into: &screen)
        return clean(screen)
    }

    private static func send(_ master: Int32, _ bytes: [UInt8]) {
        bytes.withUnsafeBufferPointer { buffer in
            _ = write(master, buffer.baseAddress, buffer.count)
        }
    }

    /// Reads whatever the CLI prints for `seconds`.
    private static func pump(_ master: Int32, for seconds: Double, into screen: inout Data) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 100) > 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let count = read(master, &buffer, buffer.count)
            if count <= 0 { return }
            screen.append(contentsOf: buffer[0..<count])
        }
    }

    /// Removes terminal control codes and returns plain text, one line per screen line.
    static func clean(_ data: Data) -> String {
        let raw = String(decoding: data, as: UTF8.self)
        let pattern = "\u{1B}\\[[0-9;?]*[ -/]*[@-~]|\u{1B}\\][^\u{07}]*\u{07}|\u{1B}[@-_]"
        let stripped = raw.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        return stripped.replacingOccurrences(of: "\r", with: "\n")
    }
}
