import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: AppDelegate?
    private var mainWindow: NSWindow?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate

        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isDemoMode = CommandLine.arguments.contains("--demo-mode")
        let viewModel = PRMonitorViewModel(isDemoMode: isDemoMode)

        let hostingController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(viewModel)
        )

        let window = NSWindow(contentViewController: hostingController)
        window.title = "MonitorLizard"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setFrameAutosaveName("MainWindow")
        window.setContentSize(NSSize(width: 450, height: 600))
        window.minSize = NSSize(width: 400, height: 400)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        mainWindow = window
        _ = UpdateService.shared
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
