import AppKit
import SwiftUI

final class DebugAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[DEBUG] applicationDidFinishLaunching fired")
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        print("[DEBUG] applicationShouldTerminate called — cancelling")
        Thread.callStackSymbols.forEach { print($0) }
        return .terminateCancel
    }
}

@main
struct MonitorLizardApp: App {
    @NSApplicationDelegateAdaptor(DebugAppDelegate.self) var appDelegate

    @StateObject private var viewModel = {
        let isDemoMode = CommandLine.arguments.contains("--demo-mode")
        return PRMonitorViewModel(isDemoMode: isDemoMode)
    }()
    private let updateService = UpdateService.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(viewModel)
        } label: {
            MenuBarLabel(showWarningIcon: viewModel.showWarningIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

struct MenuBarLabel: View {
    let showWarningIcon: Bool

    var body: some View {
        Image(systemName: showWarningIcon ? "exclamationmark.triangle.fill" : "lizard")
            .foregroundColor(showWarningIcon ? .red : nil)
    }
}
