import SwiftUI
import AppKit

private let kFloatingFrameKey = "floatingWindowFrame"

@MainActor
class WindowManager {
    static let shared = WindowManager()

    private var settingsWindow: NSWindow?
    private var floatingWindow: NSWindow?
    private(set) var isFloatingMode = false
    private let floatingWindowDelegate = FloatingWindowDelegate()

    private init() {}

    // MARK: - Add PR

    func showAddPR(viewModel: PRMonitorViewModel) {
        NSApp.windows.forEach { window in
            if window is NSPanel {
                window.orderOut(nil)
            }
        }

        let pinView = AddPRView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: pinView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Add PR"
        window.styleMask = [.titled, .closable]
        window.level = .floating
        window.center()
        window.isReleasedWhenClosed = false

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings

    func showSettings() {
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

    // MARK: - Floating Window

    private func saveFloatingFrame() {
        guard let window = floatingWindow else { return }
        let frameString = NSStringFromRect(window.frame)
        UserDefaults.standard.set(frameString, forKey: kFloatingFrameKey)
    }

    private func restoreFloatingFrame(to window: NSWindow) {
        if let frameString = UserDefaults.standard.string(forKey: kFloatingFrameKey) {
            let frame = NSRectFromString(frameString)
            if frame.width >= 100 && frame.height >= 100 {
                window.setFrame(frame, display: false)
                return
            }
        }
        // No saved frame or invalid — use default
        window.setContentSize(NSSize(width: 450, height: 600))
        window.center()
    }

    func showFloatingWindow(viewModel: PRMonitorViewModel) {
        // Close menu bar panel
        NSApp.windows.forEach { window in
            if window is NSPanel { window.orderOut(nil) }
        }

        if let window = floatingWindow {
            // Restore the saved frame before showing — NSHostingController
            // may have shrunk the window while it was hidden.
            restoreFloatingFrame(to: window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            isFloatingMode = true
            UserDefaults.standard.set(true, forKey: "useFloatingWindow")
            return
        }

        let contentView = MenuBarView()
            .environmentObject(viewModel)

        let hostingController = NSHostingController(rootView: contentView)
        // Prevent NSHostingController from shrinking the window to the
        // SwiftUI content's intrinsic size. We manage size ourselves.
        hostingController.sizingOptions = []

        let window = NSWindow(contentViewController: hostingController)
        window.title = "MonitorLizard"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.level = .floating
        window.minSize = NSSize(width: 400, height: 300)
        window.isReleasedWhenClosed = false

        restoreFloatingFrame(to: window)

        // Delegate intercepts close to hide instead of destroy,
        // preserving the window size and position.
        floatingWindowDelegate.onClose = { [weak self] in
            self?.saveFloatingFrame()
            self?.isFloatingMode = false
        }
        window.delegate = floatingWindowDelegate

        floatingWindow = window
        isFloatingMode = true
        UserDefaults.standard.set(true, forKey: "useFloatingWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideFloatingWindow() {
        saveFloatingFrame()
        floatingWindow?.orderOut(nil)
        isFloatingMode = false
        UserDefaults.standard.set(false, forKey: "useFloatingWindow")
    }

    func destroyFloatingWindow() {
        saveFloatingFrame()
        floatingWindow?.close()
        floatingWindow = nil
        isFloatingMode = false
        UserDefaults.standard.set(false, forKey: "useFloatingWindow")
    }

    func bringFloatingWindowToFront() {
        floatingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func restoreFloatingWindowIfNeeded(viewModel: PRMonitorViewModel) {
        if UserDefaults.standard.bool(forKey: "useFloatingWindow") {
            showFloatingWindow(viewModel: viewModel)
        }
    }
}

// MARK: - Floating Window Delegate

/// Intercepts the window close button (⌘W / red button) and hides the
/// window instead of destroying it, preserving the frame for next show.
class FloatingWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        onClose?()
        return false  // prevent actual close — just hide
    }
}
