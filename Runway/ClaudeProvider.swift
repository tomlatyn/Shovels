import Foundation

/// Claude Code usage: limits from the official CLI's /usage, tokens from local logs.
enum ClaudeProvider {
    static func snapshot(now: Date) throws -> ProviderSnapshot {
        let windows = try ClaudeUsageCLI.fetch(now: now)
        return ProviderSnapshot(
            provider: .claudeCode,
            plan: nil,
            windows: windows,
            asOf: now,
            tokensLast5h: tokensLast5h(now: now)
        )
    }

    /// Sums input and output tokens from assistant messages in the last five hours.
    /// Claude Code writes the same message more than once, so each message id is counted once.
    static func tokensLast5h(now: Date) -> Int? {
        guard let files = FileManager.default.enumerator(
            at: RunwayPaths.claudeProjects,
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
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            for line in text.split(separator: "\n") where line.contains("\"usage\"") {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let stamp = object["timestamp"] as? String,
                      let date = formatter.date(from: stamp), date >= cutoff,
                      let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { continue }

                let key = message["id"] as? String ?? object["uuid"] as? String ?? UUID().uuidString
                tokensByMessage[key] = (usage["input_tokens"] as? Int ?? 0) + (usage["output_tokens"] as? Int ?? 0)
            }
        }
        return tokensByMessage.values.reduce(0, +)
    }
}
