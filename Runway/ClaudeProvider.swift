import Foundation

/// Reads Claude Code usage. Limits come from the status line helper's file, tokens from local logs.
enum ClaudeProvider {
    static func snapshot(now: Date) -> ProviderSnapshot {
        var windows: [UsageWindow] = []
        var asOf: Date?

        if let data = try? Data(contentsOf: RunwayPaths.limitsFile),
           let payload = try? JSONDecoder().decode(StatusPayload.self, from: data),
           let limits = payload.rateLimits {
            windows = [
                limits.fiveHour.map { UsageWindow(label: "5H", usedPercent: $0.usedPercentage, resetsAt: Date(timeIntervalSince1970: $0.resetsAt)) },
                limits.sevenDay.map { UsageWindow(label: "WK", usedPercent: $0.usedPercentage, resetsAt: Date(timeIntervalSince1970: $0.resetsAt)) },
            ].compactMap { $0 }
            asOf = (try? FileManager.default.attributesOfItem(atPath: RunwayPaths.limitsFile.path))?[.modificationDate] as? Date
        }

        return ProviderSnapshot(
            provider: .claudeCode,
            windows: windows,
            asOf: asOf,
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

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// The part of Claude Code's status line JSON that Runway uses.
struct StatusPayload: Decodable {
    struct Window: Decodable {
        let usedPercentage: Double
        let resetsAt: Double

        enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage"
            case resetsAt = "resets_at"
        }
    }

    struct Limits: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    let rateLimits: Limits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}
