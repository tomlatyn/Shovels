import SwiftUI

@main
struct RunwayApp: App {
    @State private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(store: store)
        } label: {
            Text(store.menuBarTitle)
                .font(.system(size: 12, design: .monospaced))
        }
        .menuBarExtraStyle(.window)
    }
}
