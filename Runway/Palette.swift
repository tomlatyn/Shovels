import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Phosphor theme. Values match the design canvas.
enum Palette {
    static let ground = Color(hex: 0x0B0E0B)
    static let panel = Color(hex: 0x111612)
    static let border = Color(hex: 0x2A3A2C)
    static let phosphor = Color(hex: 0xB8F5C4)
    static let secondary = Color(hex: 0x7FA286)
    static let alert = Color(hex: 0xFF5A4E)

    static func accent(for provider: ProviderID) -> Color {
        switch provider {
        case .claudeCode: Color(hex: 0xFFA640)
        case .codex: Color(hex: 0x5BFF8A)
        }
    }
}
