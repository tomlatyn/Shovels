//
//  Formatting.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import Foundation

enum Formatting {
    /// Days and hours for long waits, hours and minutes for shorter ones.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let rest = minutes % 60
        if days > 0 {
            return hours > 0 ? "\(days) \(days == 1 ? "day" : "days") \(hours) \(hours == 1 ? "hour" : "hours")"
                             : "\(days) \(days == 1 ? "day" : "days")"
        }
        if hours > 0 {
            return rest > 0 ? "\(hours) \(hours == 1 ? "hour" : "hours") \(rest) min" : "\(hours) \(hours == 1 ? "hour" : "hours")"
        }
        return "\(max(rest, 1)) min"
    }
}
