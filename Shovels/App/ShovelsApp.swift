//
//  ShovelsApp.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import SwiftUI

@main
struct ShovelsApp: App {
    @State private var store = UsageStore()

    init() {
        ShovelsFonts.register()
#if DEBUG
        ScreenshotRenderer.renderIfRequested()
#endif
        // A CLI that exits while Shovels writes to it must not take the app down with SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
        // Quitting mid-check would otherwise leave the CLIs running.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            ChildProcess.stopAll()
        }
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
