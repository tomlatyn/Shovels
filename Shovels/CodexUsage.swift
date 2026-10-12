import Foundation

enum CodexUsageError: Error, Sendable {
    case notInstalled
    case timedOut
    case noReply

    var message: String {
        switch self {
        case .notInstalled: "Codex isn't installed where Shovels can find it."
        case .timedOut: "Codex took too long to answer."
        case .noReply: "Codex didn't return rate limits. Check that you're signed in to Codex."
        }
    }
}

/// Reads Codex's rate limits through `codex app-server`, the same protocol the Codex app uses.
/// Codex does the sign-in. Shovels never sees the login.
enum CodexUsage {
    static let candidatePaths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]

    static func snapshot(now: Date) throws -> ProviderSnapshot {
        guard let path = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw CodexUsageError.notInstalled
        }
        let reply = try request(path: path)
        return try parse(reply, now: now)
    }

    /// Starts the app server, initializes it, and asks for the account's rate limits.
    private static func request(path: String) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server"]
        process.currentDirectoryURL = ShovelsPaths.home
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
        }

        let killer = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: killer)
        defer { killer.cancel() }

        let writer = input.fileHandleForWriting
        send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": ["clientInfo": ["name": "shovels", "version": "0.1.0"]]], to: writer)
        send(["jsonrpc": "2.0", "method": "initialized"], to: writer)
        send(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read"], to: writer)

        // Read until the reply with id 2 arrives. If the server exits first, the read ends.
        let reader = output.fileHandleForReading
        var buffer = Data()
        while true {
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            for line in String(decoding: buffer, as: UTF8.self).components(separatedBy: "\n") where !line.isEmpty {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let id = object["id"] as? NSNumber, id.intValue == 2 else { continue }
                return object
            }
        }
        throw CodexUsageError.noReply
    }

    private static func send(_ message: [String: Any], to handle: FileHandle) {
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        handle.write(data)
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
