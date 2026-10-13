//
//  TerminalSession.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Darwin
import Foundation

enum TerminalSessionError: ProviderFailure {
    case couldNotStart
    /// The CLI stopped at a prompt Shovels must not answer, such as a workspace trust dialog.
    case blockedByPrompt(String)
    /// The CLI never showed its prompt. Usually it's waiting for a sign-in.
    case notReady(String)
    /// The CLI quit before it showed its prompt.
    case exited(String)

    var errorDescription: String? {
        switch self {
        case .couldNotStart: "Couldn't open a terminal session for the CLI."
        case .blockedByPrompt(let text), .notReady(let text), .exited(let text): text
        }
    }

    var needsSetup: Bool {
        switch self {
        case .couldNotStart: false
        case .blockedByPrompt, .notReady, .exited: true
        }
    }
}

/// Runs an interactive CLI inside a pseudo-terminal, types a command, and returns the screen text.
/// The CLI sees a real terminal, so commands like /usage work the same as they do in Terminal.
enum TerminalSession {
    /// Starts the CLI and waits until `ready` sees its prompt. Only then is `command` typed, one key at a time.
    /// `blocked` looks at every screen before that. If it returns a message, nothing is typed, so Shovels
    /// never answers a question such as "Do you trust this folder?".
    /// `notReady` is the message when the prompt doesn't appear within `startupSeconds`.
    static func run(
        path: String,
        directory: URL,
        command: String,
        startupSeconds: Double,
        replySeconds: Double,
        blocked: (String) -> String?,
        ready: (String) -> Bool,
        notReady: String,
        replyUntil: ((String) -> Bool)? = nil
    ) throws -> String {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else { throw TerminalSessionError.couldNotStart }
        guard grantpt(master) == 0, unlockpt(master) == 0, let namePointer = ptsname(master) else {
            close(master)
            throw TerminalSessionError.couldNotStart
        }
        let slaveName = String(cString: namePointer)
        // Hold the terminal side open while it's set up. macOS resets the size when the first holder opens it,
        // and a TUI with a 0x0 screen never draws its prompt.
        let slave = open(slaveName, O_RDWR | O_NOCTTY)
        guard slave >= 0 else {
            close(master)
            throw TerminalSessionError.couldNotStart
        }
        // TIOCSWINSZ, so the CLI lays out its screen at a readable width.
        var size = winsize(ws_row: 50, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, 0x8008_7467, &size)

        var environment = CLILocator.environment(for: path)
        environment["TERM"] = "xterm-256color"
        let child: ChildProcess
        do {
            child = try ChildProcess.spawn(
                path: path, arguments: [], directory: directory, environment: environment,
                input: .path(slaveName), output: .path(slaveName), error: .path(slaveName)
            )
        } catch {
            close(slave)
            close(master)
            throw TerminalSessionError.couldNotStart
        }
        // The CLI has its own copy open now. Closing ours lets a read on the master end when the CLI exits.
        close(slave)
        defer {
            child.stop()
            close(master)
        }

        var screen = Data()
        let deadline = Date().addingTimeInterval(startupSeconds)
        while true {
            let text = clean(screen)
            if let message = blocked(text) {
                send(master, [0x03])
                throw TerminalSessionError.blockedByPrompt(message)
            }
            if ready(text) { break }
            if child.poll() != nil { throw TerminalSessionError.exited(notReady) }
            if Date() >= deadline { throw TerminalSessionError.notReady(notReady) }
            pump(master, for: 0.5, into: &screen)
        }
        // Let the first screen finish drawing before typing.
        pump(master, for: 1.0, into: &screen)
        if let message = blocked(clean(screen)) {
            send(master, [0x03])
            throw TerminalSessionError.blockedByPrompt(message)
        }

        for byte in command.utf8 {
            send(master, [byte])
            pump(master, for: 0.1, into: &screen)
        }
        pump(master, for: 1.0, into: &screen)
        send(master, [0x0D])
        // Stop as soon as the reply is on screen, or after replySeconds.
        let replyDeadline = Date().addingTimeInterval(replySeconds)
        while Date() < replyDeadline && !(replyUntil?(clean(screen)) ?? false) && child.poll() == nil {
            pump(master, for: 0.5, into: &screen)
        }
        // One more moment, so a panel that is still repainting is complete.
        pump(master, for: 0.5, into: &screen)

        // Ctrl-C closes the panel and the CLI. `stop` then makes sure it and its helpers are gone.
        send(master, [0x03])
        pump(master, for: 0.5, into: &screen)
        return clean(screen)
    }

    private static func send(_ master: Int32, _ bytes: [UInt8]) {
        bytes.withUnsafeBufferPointer { buffer in
            _ = write(master, buffer.baseAddress, buffer.count)
        }
    }

    /// Reads whatever the CLI prints for `seconds`. Returns early if the CLI has closed the terminal.
    private static func pump(_ master: Int32, for seconds: Double, into screen: inout Data) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 100) > 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let count = read(master, &buffer, buffer.count)
            if count <= 0 {
                // Nothing more will arrive. Wait out the time without spinning.
                usleep(useconds_t(max(0, deadline.timeIntervalSinceNow) * 1_000_000))
                return
            }
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
