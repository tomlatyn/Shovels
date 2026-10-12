import AppKit

/// The Claude Code spark from the design, drawn as a template image so the menu bar tints it.
enum ProviderGlyph {
    /// 8x8 grid, "#" is filled. Same shape as the spark in the design canvas.
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

    static func image(pointSize: CGFloat = 16) -> NSImage {
        let cell = pointSize / CGFloat(spark.count)
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { _ in
            NSColor.black.setFill()
            for (row, line) in spark.enumerated() {
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
