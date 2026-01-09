import SwiftUI

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval = Constants.defaultRefreshInterval
    @AppStorage("sortNonSuccessFirst") private var sortNonSuccessFirst = false
    @AppStorage("showReviewPRs") private var showReviewPRs = true
    @AppStorage("enableSounds") private var enableSounds = true
    @AppStorage("enableVoice") private var enableVoice = true
    @AppStorage("voiceAnnouncementText") private var voiceAnnouncementText = Constants.defaultVoiceAnnouncementText
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("enableStaleBranchDetection") private var enableStaleBranchDetection = false
    @AppStorage("staleBranchThresholdDays") private var staleBranchThresholdDays = Constants.defaultStaleBranchThreshold

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
                            get: { Double(refreshInterval) },
                            set: { refreshInterval = Int($0) }
                        ), in: Double(Constants.minRefreshInterval)...Double(Constants.maxRefreshInterval), step: Double(Constants.refreshIntervalStep))

                        Text("\(refreshInterval)s")
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
                    Toggle("Sort non-success PRs first", isOn: $sortNonSuccessFirst)
                        .help("Show PRs with pending, failed, or error status at the top of the list")

                    Text("Success (green) PRs will appear at the bottom")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show PRs awaiting my review", isOn: $showReviewPRs)
                        .help("Display pull requests where you are a requested reviewer")

                    Text("Review PRs appear at the top to prioritize unblocking teammates")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Stale Branch Detection") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable stale branch detection", isOn: $enableStaleBranchDetection)
                        .help("Highlight PRs that haven't been updated in a while")

                    if enableStaleBranchDetection {
                        Stepper("Days without update: \(staleBranchThresholdDays)",
                                value: $staleBranchThresholdDays,
                                in: Constants.minStaleBranchThreshold...Constants.maxStaleBranchThreshold)
                            .padding(.top, 4)

                        Text("PRs not updated for \(staleBranchThresholdDays) days will show as stale")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("About Polling")
                        .font(.headline)

                    Text("MonitorLizard polls GitHub every \(refreshInterval) seconds to check the build status of your open pull requests. Lower values provide faster updates but may consume more resources.")
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
                Toggle("Show notifications", isOn: $showNotifications)
                    .help("Display macOS notifications when watched builds complete")

                Toggle("Play sounds", isOn: $enableSounds)
                    .help("Play sound effects when builds complete")

                Toggle("Voice announcements", isOn: $enableVoice)
                    .help("Speak announcement text when successful builds complete")

                if enableVoice {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Announcement text")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("", text: $voiceAnnouncementText, prompt: Text("Build ready for Q A"))
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

                Text("Version 1.0.0")
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

                HStack(spacing: 20) {
                    Button("GitHub CLI") {
                        if let url = URL(string: "https://cli.github.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    Button("Report Issue") {
                        if let url = URL(string: "https://github.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }
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

// Preview
#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
