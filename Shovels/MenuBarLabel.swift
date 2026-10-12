import SwiftUI

/// Menu bar item: each provider's glyph, then its percentage.
struct MenuBarLabel: View {
    let store: UsageStore

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: ProviderGlyph.image(rows: ProviderGlyph.shovel))
            ForEach(UsageStore.menuProviders, id: \.self) { provider in
                HStack(spacing: 3) {
                    Image(nsImage: ProviderGlyph.image(for: provider))
                    Text(store.menuText(for: provider))
                        .font(Retro.body(17))
                }
            }
        }
        .help(store.menuBarHelp)
    }
}
