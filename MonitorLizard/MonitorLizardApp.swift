import SwiftUI

@main
struct MonitorLizardApp: App {
    @StateObject private var viewModel = {
        let isDemoMode = CommandLine.arguments.contains("--demo-mode")
        return PRMonitorViewModel(isDemoMode: isDemoMode)
    }()
    @State private var didRestoreFloatingWindowAtLaunch = false
    private let updateService = UpdateService.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(viewModel)
        } label: {
            MenuBarLabel(showWarningIcon: viewModel.showWarningIcon)
                .task {
                    guard !didRestoreFloatingWindowAtLaunch else { return }
                    didRestoreFloatingWindowAtLaunch = true
                    WindowManager.shared.restoreFloatingWindowIfNeeded(viewModel: viewModel)
                }
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
