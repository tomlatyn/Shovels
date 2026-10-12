import SwiftUI

/// Menu bar item: the Claude spark, then the 5-hour percentage.
struct MenuBarLabel: View {
    let store: UsageStore

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: ProviderGlyph.image())
            Text(store.menuBarText)
                .font(Retro.body(17))
        }
    }
}
