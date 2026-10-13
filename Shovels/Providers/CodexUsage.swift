//
//  CodexUsage.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation

enum CodexUsageError: ProviderFailure {
    case timedOut
    case noReply
    /// Codex answered with an error, such as a sign-in problem. The text is Codex's own.
    case server(String)

    var errorDescription: String? {
        switch self {
        case .timedOut: "Codex took too long to answer. Shovels will try again."
        case .noReply: "Codex didn't return rate limits. Run 'codex login' in Terminal and check that you're signed in."
        case .server(let message): "Codex said: \(message)"
        }
    }

    var needsSetup: Bool {
        switch self {
        case .timedOut: false
        case .noReply, .server: true
        }
    }
}

/// Reads Codex's rate limits through `codex app-server`, the same protocol the Codex app uses.
/// Codex does the sign-in. Shovels never sees the login.
enum CodexUsage {
    static func snapshot(now: Date) throws -> ProviderSnapshot {
        let path = try CLILocator.locate("codex")
        let reply = try request(path: path)
        return try parse(reply, now: now)
    }

    /// Starts the app server, initializes it, and asks for the account's rate limits.
    private static func request(path: String) throws -> [String: Any] {
        var inPipe: [Int32] = [0, 0]
        var outPipe: [Int32] = [0, 0]
        guard pipe(&inPipe) == 0 else { throw ChildProcessError.couldNotStart("pipe failed") }
        guard pipe(&outPipe) == 0 else {
            inPipe.forEach { close($0) }
            throw ChildProcessError.couldNotStart("pipe failed")
        }
        let child: ChildProcess
        do {
            child = try ChildProcess.spawn(
                path: path, arguments: ["app-server"], directory: ShovelsPaths.home,
                environment: CLILocator.environment(for: path),
                input: .descriptor(inPipe[0]), output: .descriptor(outPipe[1]), error: .null
            )
        } catch {
            (inPipe + outPipe).forEach { close($0) }
            throw error
        }
        close(inPipe[0])
        close(outPipe[1])
        defer {
            close(inPipe[1])
            close(outPipe[0])
            child.stop()
        }

        let writer = inPipe[1]
        send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": ["clientInfo": ["name": "shovels", "version": "0.1.0"]]], to: writer)
        send(["jsonrpc": "2.0", "method": "initialized"], to: writer)
        send(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read"], to: writer)

        // Read lines until the reply with id 2 arrives, the server exits, or 20 seconds pass.
        let deadline = Date().addingTimeInterval(20)
        var pending = Data()
        while Date() < deadline {
            var descriptor = pollfd(fd: outPipe[0], events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 100) > 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let count = read(outPipe[0], &buffer, buffer.count)
            if count <= 0 { throw CodexUsageError.noReply }
            pending.append(contentsOf: buffer[0..<count])
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = object["id"] as? NSNumber, id.intValue == 2 else { continue }
                if let error = object["error"] as? [String: Any] {
                    throw CodexUsageError.server(error["message"] as? String ?? "unknown error")
                }
                return object
            }
        }
        throw CodexUsageError.timedOut
    }

    private static func send(_ message: [String: Any], to descriptor: Int32) {
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        // Shovels ignores SIGPIPE, so a server that already exited only makes this write fail.
        // The read loop then reports no reply.
        data.withUnsafeBytes { _ = write(descriptor, $0.baseAddress, $0.count) }
    }

    /// Reads the primary and secondary windows from a `rateLimits` reply.
    static func parse(_ reply: [String: Any], now: Date) throws -> ProviderSnapshot {
        guard let result = reply["result"] as? [String: Any],
              let limits = result["rateLimits"] as? [String: Any] else {
            throw CodexUsageError.noReply
        }

        var windows: [UsageWindow] = []
        for key in ["primary", "secondary"] {
            guard let window = limits[key] as? [String: Any],
                  let minutes = (window["windowDurationMins"] as? NSNumber)?.intValue else { continue }
            windows.append(UsageWindow(
                title: title(forMinutes: minutes),
                minutes: minutes,
                usedPercent: (window["usedPercent"] as? NSNumber)?.doubleValue,
                resetsAt: (window["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            ))
        }
        guard !windows.isEmpty else { throw CodexUsageError.noReply }

        return ProviderSnapshot(
            provider: .codex,
            plan: (limits["planType"] as? String)?.uppercased(),
            windows: windows,
            asOf: now,
            tokensLast5h: nil
        )
    }

    private static func title(forMinutes minutes: Int) -> String {
        switch minutes {
        case 300: "Session"
        case 10080: "Weekly"
        case 43200: "Monthly"
        default: "\(minutes / 60) hours"
        }
    }
}
