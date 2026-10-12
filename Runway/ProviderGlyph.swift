import AppKit

/// Pixel glyphs from the design, drawn as template images so the menu bar tints them.
enum ProviderGlyph {
    /// 8x8 grids, "#" is filled.
    static let spark = [
        "...##...",
        ".#.##.#.",
        "...##...",
        "########",
        "########",
        "...##...",
        ".#.##.#.",
        "...##...",
    ]

    static let chevron = [
        "........",
        ".#......",
        "..#.....",
        "...#....",
        "..#.....",
        ".#......",
        ".....###",
        "........",
    ]

    static func grid(for provider: ProviderID) -> [String] {
        switch provider {
        case .claudeCode: spark
        case .codex: chevron
        }
    }

    static func image(for provider: ProviderID, pointSize: CGFloat = 16) -> NSImage {
        let rows = grid(for: provider)
        let cell = pointSize / CGFloat(rows.count)
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { _ in
            NSColor.black.setFill()
            for (row, line) in rows.enumerated() {
                for (column, mark) in line.enumerated() where mark == "#" {
                    NSRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
