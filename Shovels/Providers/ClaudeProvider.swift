//
//  ClaudeProvider.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation

/// Claude Code usage: limits from the official CLI's /usage, tokens from local logs.
enum ClaudeProvider {
    static func snapshot(now: Date) throws -> ProviderSnapshot {
        let path = try CLILocator.locate("claude")
        let windows = try ClaudeUsageCLI.fetch(path: path, now: now)
        return ProviderSnapshot(
            provider: .claudeCode,
            plan: ClaudeUsageCLI.plan(path: path),
            windows: windows,
            asOf: now,
            tokensLast5h: tokensLast5h(now: now)
        )
    }

    /// The last `maxBytes` of a log, so a very large file doesn't load whole on every refresh.
    /// The first line is dropped when the read starts mid-line.
    static func tail(of url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return text
    }

    /// Sums input and output tokens from assistant messages in the last five hours.
    /// Claude Code writes the same message more than once, so each message id is counted once.
    static func tokensLast5h(now: Date) -> Int? {
        guard let files = FileManager.default.enumerator(
            at: ShovelsPaths.claudeProjects,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let cutoff = now.addingTimeInterval(-5 * 3600)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var tokensByMessage: [String: Int] = [:]

        for case let url as URL in files where url.pathExtension == "jsonl" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let modified, modified >= cutoff,
                  let text = tail(of: url, maxBytes: 32 * 1024 * 1024) else { continue }

            for line in text.split(separator: "\n") where line.contains("\"usage\"") {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let stamp = object["timestamp"] as? String,
                      let date = formatter.date(from: stamp), date >= cutoff,
                      let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let key = message["id"] as? String ?? object["uuid"] as? String else { continue }

                tokensByMessage[key] = (usage["input_tokens"] as? Int ?? 0) + (usage["output_tokens"] as? Int ?? 0)
            }
        }
        return tokensByMessage.values.reduce(0, +)
    }
}
