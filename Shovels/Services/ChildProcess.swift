//
//  ChildProcess.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Darwin
import Foundation
import os

enum ChildProcessError: ProviderFailure {
    case couldNotStart(String)

    var errorDescription: String? {
        switch self {
        case .couldNotStart(let reason): "Couldn't start the CLI: \(reason)."
        }
    }

    var needsSetup: Bool { true }
}

/// A CLI started in its own session and process group, so it and everything it starts can be stopped together.
/// Foundation's Process only signals the direct child, which left node and TUI helpers running after a check.
final class ChildProcess: @unchecked Sendable {
    let pid: pid_t
    private let lock = NSLock()
    private var exitStatus: Int32?

    /// Every process group still running, so quitting Shovels can stop them.
    private static let running = OSAllocatedUnfairLock(initialState: Set<pid_t>())

    /// What the child gets as stdin, stdout, and stderr.
    enum Stream {
        case descriptor(Int32)
        case path(String)
        case null
    }

    private init(pid: pid_t) {
        self.pid = pid
    }

    /// Starts `path` with a new session. The child keeps only the three streams given here; every other
    /// descriptor is closed, so one CLI can't hold another CLI's pipe open.
    static func spawn(
        path: String,
        arguments: [String],
        directory: URL,
        environment: [String: String],
        input: Stream,
        output: Stream,
        error: Stream
    ) throws -> ChildProcess {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        // Start with default signal handling, even though Shovels ignores SIGPIPE.
        var defaults = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGPIPE)
        posix_spawnattr_setsigdefault(&attributes, &defaults)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        if #available(macOS 26, *) {
            posix_spawn_file_actions_addchdir(&actions, directory.path)
        } else {
            posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        }
        for (target, stream) in [(Int32(0), input), (1, output), (2, error)] {
            switch stream {
            case .descriptor(let fd):
                posix_spawn_file_actions_adddup2(&actions, fd, target)
            case .path(let file):
                posix_spawn_file_actions_addopen(&actions, target, file, O_RDWR, 0)
            case .null:
                posix_spawn_file_actions_addopen(&actions, target, "/dev/null", O_RDWR, 0)
            }
        }

        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, path, &actions, &attributes, argv, envp)
        guard result == 0 else {
            throw ChildProcessError.couldNotStart(String(cString: strerror(result)))
        }
        let spawned = pid
        running.withLock { _ = $0.insert(spawned) }
        return ChildProcess(pid: spawned)
    }

    /// The exit status once the process has ended, or nil while it runs. Reaps the process.
    func poll() -> Int32? {
        lock.withLock {
            if let exitStatus { return exitStatus }
            var status: Int32 = 0
            guard waitpid(pid, &status, WNOHANG) == pid else { return nil }
            exitStatus = Self.decode(status)
            return exitStatus
        }
    }

    /// Waits up to `seconds` for the process to end on its own.
    func wait(seconds: Double) -> Int32? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let status = poll() { return status }
            usleep(50_000)
        }
        return poll()
    }

    /// Stops the whole process group: SIGTERM, then SIGKILL if anything is left after `grace` seconds.
    /// The group is signalled even after the leader exits, because helpers it started may still run.
    func stop(grace: Double = 2) {
        killpg(pid, SIGTERM)
        if wait(seconds: grace) == nil || groupIsAlive() {
            killpg(pid, SIGKILL)
            _ = wait(seconds: 1)
        }
        Self.running.withLock { _ = $0.remove(pid) }
    }

    private func groupIsAlive() -> Bool {
        killpg(pid, 0) == 0
    }

    /// Kills every CLI Shovels started. Called when the app quits.
    static func stopAll() {
        for group in running.withLock({ $0 }) {
            killpg(group, SIGKILL)
        }
    }

    private static func decode(_ status: Int32) -> Int32 {
        let signal = status & 0x7F
        return signal == 0 ? (status >> 8) & 0xFF : 128 + signal
    }
}

/// Runs a CLI to completion with a time limit, capturing stdout and stderr separately.
enum CommandRunner {
    struct Output: Sendable {
        var stdout: String
        var stderr: String
        var status: Int32?
        var timedOut: Bool
    }

    /// `environment` defaults to the CLI environment from CLILocator.
    static func run(path: String, arguments: [String], directory: URL, timeout: Double,
                    environment: [String: String]? = nil) throws -> Output {
        var outPipe: [Int32] = [0, 0]
        var errPipe: [Int32] = [0, 0]
        guard pipe(&outPipe) == 0 else { throw ChildProcessError.couldNotStart("pipe failed") }
        guard pipe(&errPipe) == 0 else {
            close(outPipe[0]); close(outPipe[1])
            throw ChildProcessError.couldNotStart("pipe failed")
        }
        let child: ChildProcess
        do {
            child = try ChildProcess.spawn(
                path: path, arguments: arguments, directory: directory,
                environment: environment ?? CLILocator.environment(for: path),
                input: .null, output: .descriptor(outPipe[1]), error: .descriptor(errPipe[1])
            )
        } catch {
            outPipe.forEach { close($0) }
            errPipe.forEach { close($0) }
            throw error
        }
        close(outPipe[1])
        close(errPipe[1])
        defer {
            close(outPipe[0])
            close(errPipe[0])
        }

        var out = Data()
        var err = Data()
        var open: [Int32] = [outPipe[0], errPipe[0]]
        let deadline = Date().addingTimeInterval(timeout)
        while !open.isEmpty && Date() < deadline {
            var descriptors = open.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
            guard Darwin.poll(&descriptors, nfds_t(descriptors.count), 100) > 0 else { continue }
            for descriptor in descriptors where descriptor.revents != 0 {
                var buffer = [UInt8](repeating: 0, count: 65_536)
                let count = read(descriptor.fd, &buffer, buffer.count)
                if count <= 0 {
                    open.removeAll { $0 == descriptor.fd }
                } else if descriptor.fd == outPipe[0] {
                    out.append(contentsOf: buffer[0..<count])
                } else {
                    err.append(contentsOf: buffer[0..<count])
                }
            }
        }
        let timedOut = !open.isEmpty
        let status = timedOut ? nil : child.wait(seconds: max(0, deadline.timeIntervalSinceNow))
        child.stop()
        return Output(
            stdout: String(decoding: out, as: UTF8.self),
            stderr: String(decoding: err, as: UTF8.self),
            status: status,
            timedOut: timedOut || status == nil
        )
    }
}
