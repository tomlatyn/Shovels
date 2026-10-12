import SwiftUI

@main
struct RunwayApp: App {
    @State private var store = UsageStore()

    init() {
        RunwayFonts.register()
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(store: store)
        } label: {
            Text(store.menuBarTitle)
                .font(Retro.body(16))
        }
        .menuBarExtraStyle(.window)
    }
}
