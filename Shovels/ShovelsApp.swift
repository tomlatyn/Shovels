import SwiftUI

@main
struct ShovelsApp: App {
    @State private var store = UsageStore()

    init() {
        ShovelsFonts.register()
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
