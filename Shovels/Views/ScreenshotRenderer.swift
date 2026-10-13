//
//  ScreenshotRenderer.swift
//  Shovels
//

#if DEBUG

import AppKit
import SwiftUI

/// Renders the dashboard with demo readings to a PNG for the README.
/// Run with `--render-screenshot <path>`, as scripts/update_screenshot.command does.
enum ScreenshotRenderer {

    static func renderIfRequested() {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--render-screenshot"),
              flagIndex + 1 < arguments.count else {
            return
        }

        let outputURL = URL(fileURLWithPath: arguments[flagIndex + 1])
        MainActor.assumeIsolated {
            render(to: outputURL)
        }
        exit(0)
    }

    @MainActor
    private static func render(to url: URL) {
        let now = Date()
        let store = UsageStore(screenshotStates: demoStates(now: now), now: now)
        let content = DashboardView(store: store)
            .padding(24)
            .background(Color.black)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard let cgImage = renderer.cgImage else {
            fail("failed to render image")
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            fail("failed to encode PNG")
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
            print("Screenshot written to \(url.path)")
        } catch {
            fail("failed to write \(url.path): \(error)")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("ScreenshotRenderer: \(message)\n".utf8))
        exit(1)
    }

    private static func demoStates(now: Date) -> [ProviderID: ProviderState] {
        func window(_ title: String, _ minutes: Int, _ used: Double, resetsIn: TimeInterval, group: String? = nil) -> UsageWindow {
            UsageWindow(title: title, group: group, minutes: minutes, usedPercent: used,
                        resetsAt: now.addingTimeInterval(resetsIn))
        }

        func state(_ provider: ProviderID, plan: String, tokens: Int? = nil, _ windows: [UsageWindow]) -> ProviderState {
            ProviderState(snapshot: ProviderSnapshot(provider: provider, plan: plan, windows: windows,
                                                     asOf: now, tokensLast5h: tokens))
        }

        return [
            .claudeCode: state(.claudeCode, plan: "Max", tokens: 1_840_000, [
                window("Session", 300, 62, resetsIn: 2 * 3600 + 900),
                window("Weekly", 10_080, 38, resetsIn: 4 * 86_400),
            ]),
            .codex: state(.codex, plan: "Plus", [
                window("Monthly", 43_200, 14, resetsIn: 18 * 86_400),
            ]),
            .antigravity: state(.antigravity, plan: "Pro", [
                window("Session", 300, 40, resetsIn: 3_600, group: "GEMINI"),
                window("Weekly", 10_080, 71, resetsIn: 3 * 86_400, group: "GEMINI"),
            ]),
            .cursor: state(.cursor, plan: "Pro", [
                window("Included", 43_200, 91, resetsIn: 9 * 86_400),
            ]),
        ]
    }
}

#endif
