import AppKit
import Dependencies
import SwiftUI

#if DEBUG
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
#endif

@main
struct MonitorLizardApp: App {
    #if DEBUG
    @NSApplicationDelegateAdaptor(DebugAppDelegate.self) var appDelegate
    #endif

    @StateObject private var viewModel = {
        let isDemoMode = CommandLine.arguments.contains("--demo-mode")
        return PRMonitorViewModel(isDemoMode: isDemoMode)
    }()
    private let updateService = UpdateService.shared

    init() {
        prepareDependencies {
            $0.userDefaults.register(defaults: [
                PreferenceKeys.refreshInterval.rawValue: Constants.defaultRefreshInterval,
                PreferenceKeys.sortNonSuccessFirst.rawValue: false,
                PreferenceKeys.showReviewPRs.rawValue: true,
                PreferenceKeys.enableSounds.rawValue: true,
                PreferenceKeys.enableVoice.rawValue: true,
                PreferenceKeys.showNotifications.rawValue: true,
                PreferenceKeys.voiceAnnouncementTextBuildComplete.rawValue: Constants.defaultVoiceAnnouncementTextBuildComplete,
                PreferenceKeys.voiceAnnouncementTextPRUpdated.rawValue: Constants.defaultVoiceAnnouncementTextPRUpdated,
                PreferenceKeys.enableInactiveBranchDetection.rawValue: false,
                PreferenceKeys.hideInactivePRs.rawValue: false,
                PreferenceKeys.inactiveBranchThresholdDays.rawValue: Constants.defaultInactiveBranchThreshold,
                PreferenceKeys.selectedRepository.rawValue: "All Repositories",
            ])
        }
    }

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