import AppKit

/// Pixel glyphs from the design, drawn as template images so the menu bar tints them.
enum ProviderGlyph {
    /// 8x8 grids, "#" is filled.
    static let spark = [
        "................",
        ".......##.......",
        "....#..##..#....",
        ".....#.##.#.....",
        "..#..######..#..",
        "...##########...",
        "....########....",
        "..############..",
        "..############..",
        "....########....",
        "..############..",
        "..#..######..#..",
        ".....#.##.#.....",
        "....#..##..#....",
        "................",
        "................",
    ]

    static let chevron = [
        "............",
        "..#.........",
        "...#........",
        "....#.......",
        ".....#......",
        "....#.......",
        "...#........",
        "..#.........",
        "............",
        "......#####.",
        "............",
        "............",
    ]

    /// Shovel for the app itself: a diagonal handle running into a spade at the bottom left.
    static let shovel = [
        "......##",
        ".....##.",
        "....##..",
        "..###...",
        ".#####..",
        ".#####..",
        "..###...",
        "........",
    ]

    /// Antigravity: an arch with a crossbar.
    static let arch = [
        "................",
        ".......##.......",
        "......####......",
        ".....######.....",
        "....########....",
        "...##########...",
        "..####....####..",
        "..###......###..",
        ".###........###.",
        ".###........###.",
        "###..........###",
        "##............##",
        "##............##",
        ".#............#.",
        "................",
        "................",
    ]

    static let pointer = [
        "................",
        ".....######.....",
        "....########....",
        "...##########...",
        "...##########...",
        "..#.........##..",
        "..##.......###..",
        ".###.......####.",
        ".####.....#####.",
        "..###.....####..",
        "..###....#####..",
        "...###..#####...",
        "...###..#####...",
        "....########....",
        ".....######.....",
        "................",
    ]

    static func grid(for provider: ProviderID) -> [String] {
        switch provider {
        case .claudeCode: spark
        case .codex: chevron
        case .antigravity: arch
        case .cursor: pointer
        }
    }

    static func image(for provider: ProviderID, pointSize: CGFloat = 16) -> NSImage {
        image(rows: grid(for: provider), pointSize: pointSize)
    }

    /// Draws a grid as a template image, so the menu bar and the dashboard tint it.
    static func image(rows: [String], pointSize: CGFloat = 16) -> NSImage {
        let cell = pointSize / CGFloat(max(rows.count, rows.first?.count ?? 1))
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
