import AppKit
import SwiftUI

@main
struct GraphistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Every window (File ▸ New Window, ⌘N) gets its own canvas, renderer and scene.
        WindowGroup("Graphist", id: "canvas") {
            CanvasWindow()
        }
        .defaultSize(width: 1100, height: 760)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`, Xcode) rather
        // than from the .app bundle, so the app gets a Dock icon and menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}
