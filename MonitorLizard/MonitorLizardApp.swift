import SwiftUI

@main
struct MonitorLizardApp: App {
    @StateObject private var viewModel = PRMonitorViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(viewModel)
        } label: {
            MenuBarLabel(hasFailingBuilds: viewModel.hasFailingBuilds)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

struct MenuBarLabel: View {
    let hasFailingBuilds: Bool

    var body: some View {
        Image(systemName: hasFailingBuilds ? "exclamationmark.triangle.fill" : "lizard")
            .foregroundColor(hasFailingBuilds ? .red : nil)
    }
}
