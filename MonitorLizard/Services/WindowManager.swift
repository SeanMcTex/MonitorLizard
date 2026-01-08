import SwiftUI
import AppKit

@MainActor
class WindowManager {
    static let shared = WindowManager()

    private var settingsWindow: NSWindow?

    private init() {}

    func showSettings() {
        // Close the menu bar extra by ordering out all panels
        NSApp.windows.forEach { window in
            if window is NSPanel {
                window.orderOut(nil)
            }
        }

        if let window = settingsWindow {
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "MonitorLizard Settings"
        window.styleMask = [.titled, .closable]
        window.level = .floating
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.isReleasedWhenClosed = false

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
