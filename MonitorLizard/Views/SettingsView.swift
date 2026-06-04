import Dependencies
import SwiftUI

struct SettingsView: View {
    @Dependency(UserDefaultsStore.self) private var defaults

    private var refreshInterval: Binding<Int> {
        Binding(
            get: { defaults.object(forKey: PreferenceKeys.refreshInterval) as? Int ?? Constants.defaultRefreshInterval },
            set: { defaults.set($0, forKey: PreferenceKeys.refreshInterval) }
        )
    }

    private var sortNonSuccessFirst: Binding<Bool> {
        Binding(
            get: { defaults.bool(forKey: PreferenceKeys.sortNonSuccessFirst) },
            set: { defaults.set($0, forKey: PreferenceKeys.sortNonSuccessFirst) }
        )
    }

    private var showReviewPRs: Binding<Bool> {
        Binding(
            get: { defaults.object(forKey: PreferenceKeys.showReviewPRs) as? Bool ?? true },
            set: { defaults.set($0, forKey: PreferenceKeys.showReviewPRs) }
        )
    }

    private var enableSounds: Binding<Bool> {
        Binding(
            get: { defaults.object(forKey: PreferenceKeys.enableSounds) as? Bool ?? true },
            set: { defaults.set($0, forKey: PreferenceKeys.enableSounds) }
        )
    }

    private var enableVoice: Binding<Bool> {
        Binding(
            get: { defaults.object(forKey: PreferenceKeys.enableVoice) as? Bool ?? true },
            set: { defaults.set($0, forKey: PreferenceKeys.enableVoice) }
        )
    }

    private var voiceAnnouncementText: Binding<String> {
        Binding(
            get: { defaults.string(forKey: PreferenceKeys.voiceAnnouncementText) ?? Constants.defaultVoiceAnnouncementText },
            set: { defaults.set($0, forKey: PreferenceKeys.voiceAnnouncementText) }
        )
    }

    private var showNotifications: Binding<Bool> {
        Binding(
            get: { defaults.object(forKey: PreferenceKeys.showNotifications) as? Bool ?? true },
            set: { defaults.set($0, forKey: PreferenceKeys.showNotifications) }
        )
    }

    private var enableInactiveBranchDetection: Binding<Bool> {
        Binding(
            get: { defaults.bool(forKey: PreferenceKeys.enableInactiveBranchDetection) },
            set: { defaults.set($0, forKey: PreferenceKeys.enableInactiveBranchDetection) }
        )
    }

    private var hideInactivePRs: Binding<Bool> {
        Binding(
            get: { defaults.bool(forKey: PreferenceKeys.hideInactivePRs) },
            set: { defaults.set($0, forKey: PreferenceKeys.hideInactivePRs) }
        )
    }

    private var inactiveBranchThresholdDays: Binding<Int> {
        Binding(
            get: { defaults.object(forKey: PreferenceKeys.inactiveBranchThresholdDays) as? Int ?? Constants.defaultInactiveBranchThreshold },
            set: { defaults.set($0, forKey: PreferenceKeys.inactiveBranchThresholdDays) }
        )
    }

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            notificationSettings
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            aboutView
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: Constants.settingsWindowWidth, height: Constants.settingsWindowHeight)
        .padding()
    }

    private var generalSettings: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Refresh Interval")
                        .font(.headline)

                    HStack {
                        Slider(value: Binding(
                            get: { Double(refreshInterval.wrappedValue) },
                            set: { refreshInterval.wrappedValue = Int($0) }
                        ), in: Double(Constants.minRefreshInterval)...Double(Constants.maxRefreshInterval), step: Double(Constants.refreshIntervalStep))

                        Text("\(refreshInterval.wrappedValue)s")
                            .frame(width: 50, alignment: .trailing)
                            .foregroundColor(.secondary)
                    }

                    Text("How often to check for PR status updates")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Sort non-success PRs first", isOn: sortNonSuccessFirst)
                        .help("Show PRs with pending, failed, or error status at the top of the list")

                    Text("Success (green) PRs will appear at the bottom")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show PRs awaiting my review", isOn: showReviewPRs)
                        .help("Display pull requests where you are a requested reviewer")

                    Text("Review PRs appear at the top to prioritize unblocking teammates")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Inactive Branch Detection") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable inactive branch detection", isOn: enableInactiveBranchDetection)
                        .help("Highlight PRs that haven't been updated in a while")

                    if enableInactiveBranchDetection.wrappedValue {
                        Stepper("Days without update: \(inactiveBranchThresholdDays.wrappedValue)",
                                value: inactiveBranchThresholdDays,
                                in: Constants.minInactiveBranchThreshold...Constants.maxInactiveBranchThreshold)
                            .padding(.top, 4)

                        Text("PRs not updated for \(inactiveBranchThresholdDays.wrappedValue) days will show as inactive")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        Toggle("Hide inactive PRs", isOn: hideInactivePRs)
                            .help("Completely hide inactive PRs from the list instead of showing them with a warning")
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("About Polling")
                        .font(.headline)

                    Text("MonitorLizard polls GitHub every \(refreshInterval.wrappedValue) seconds to check the build status of your open pull requests. Lower values provide faster updates but may consume more resources.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
    }

    private var notificationSettings: some View {
        Form {
            Section {
                Toggle("Show notifications", isOn: showNotifications)
                    .help("Display macOS notifications when watched builds complete")

                Toggle("Play sounds", isOn: enableSounds)
                    .help("Play sound effects when builds complete")

                Toggle("Voice announcements", isOn: enableVoice)
                    .help("Speak announcement text when successful builds complete")

                if enableVoice.wrappedValue {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Announcement text")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("", text: voiceAnnouncementText, prompt: Text("Build ready for Q A"))
                            .textFieldStyle(.roundedBorder)
                            .help("The text that will be spoken when a watched build completes successfully")
                    }
                    .padding(.leading, 20)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How Watching Works")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "eye")
                                .foregroundColor(.blue)
                                .frame(width: 20)

                            Text("Click the eye icon on any PR to watch it for completion")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "bell.badge")
                                .foregroundColor(.orange)
                                .frame(width: 20)

                            Text("You'll be notified when the build status changes from pending to complete")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                                .frame(width: 20)

                            Text("Notifications appear for success, failure, and error states")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
    }

    private var aboutView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lizard")
                .font(.system(size: 60))
                .foregroundColor(.green)

            VStack(spacing: 8) {
                Text("MonitorLizard")
                    .font(.title)
                    .fontWeight(.bold)

                Text("GitHub PR Build Monitor")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 12) {
                Text("Monitors your GitHub pull requests and notifies you when builds complete.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Divider()
                    .padding(.horizontal, 40)

                VStack(spacing: 6) {
                    Text("Credits")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Text("Maintained by Sean \"Sharky\" McMains")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("Contributors")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    Text("Kaijian Ding · John T McIntosh · Luke LaBonte · Buqian Zheng")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)

                HStack(spacing: 20) {
                    Button("GitHub CLI") {
                        if let url = URL(string: "https://cli.github.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    Button("Report Issue") {
                        if let url = URL(string: "https://github.com/SeanMcTex/MonitorLizard/issues") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    Button("Check for Updates...") {
                        UpdateService.shared.checkForUpdates()
                    }
                    .disabled(!UpdateService.shared.canCheckForUpdates)
                }
            }

            Spacer()

            Text("Built with Swift and SwiftUI")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#if DEBUG
#Preview {
    SettingsView()
}
#endif