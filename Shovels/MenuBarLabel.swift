import SwiftUI

/// Menu bar item: the main provider's glyph and percentage. Falls back to the shovel when nothing is on.
struct MenuBarLabel: View {
    let store: UsageStore

    var body: some View {
        HStack(spacing: 4) {
            if let provider = store.menuProvider {
                Image(nsImage: ProviderGlyph.image(for: provider))
                Text(store.menuText(for: provider))
                    .font(Retro.body(17))
            } else {
                Image(nsImage: ProviderGlyph.image(rows: ProviderGlyph.shovel))
            }
        }
        .help(store.menuBarHelp)
    }
}
