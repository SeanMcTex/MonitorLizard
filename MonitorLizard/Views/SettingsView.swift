import SwiftUI

struct SettingsView: View {
    private static let globalRulesSelectionId = "global_rules"
    private static let globalIgnoredReposKey = "globalIgnoredReposData"
    private static let globalIgnoredChecksKey = "globalIgnoredChecksData"

    @AppStorage("refreshInterval") private var refreshInterval = Constants.defaultRefreshInterval
    @AppStorage("disableAutoRefresh") private var disableAutoRefresh = false
    @AppStorage("refreshOnStartup") private var refreshOnStartup = true
    @AppStorage("enableQuietHours") private var enableQuietHours = false
    @AppStorage("quietHoursStart") private var quietHoursStart = Constants.defaultQuietHoursStart
    @AppStorage("quietHoursEnd") private var quietHoursEnd = Constants.defaultQuietHoursEnd
    @AppStorage("quietHoursSkipWeekends") private var quietHoursSkipWeekends = true
    @AppStorage("sortNonSuccessFirst") private var sortNonSuccessFirst = false
    @AppStorage("showReviewPRs") private var showReviewPRs = true
    @AppStorage("enableSounds") private var enableSounds = true
    @AppStorage("enableVoice") private var enableVoice = true
    @AppStorage("voiceAnnouncementText") private var voiceAnnouncementText = Constants.defaultVoiceAnnouncementText
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("enableInactiveBranchDetection") private var enableInactiveBranchDetection = false
    @AppStorage("inactiveBranchThresholdDays") private var inactiveBranchThresholdDays = Constants.defaultInactiveBranchThreshold
    @AppStorage("hideInactivePRs") private var hideInactivePRs = false
    @AppStorage("useFloatingWindow") private var useFloatingWindow = false
    @AppStorage(Self.globalIgnoredReposKey) private var globalIgnoredReposData: Data = Data()
    @AppStorage(Self.globalIgnoredChecksKey) private var globalIgnoredChecksData: Data = Data()

    @StateObject private var monitoredUsersService = MonitoredUsersService.shared

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            usersSettings
                .tabItem {
                    Label("Users", systemImage: "person.2")
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

    // MARK: - General

    private var generalSettings: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Refresh Interval")
                        .font(.headline)

                    Toggle("Disable auto refresh", isOn: $disableAutoRefresh)
                        .help("Only refresh manually via the refresh button")

                    Toggle("Refresh on startup", isOn: $refreshOnStartup)
                        .help("When off, uses cached data on launch and waits for the next scheduled refresh")

                    if !disableAutoRefresh {
                        HStack {
                            Slider(value: Binding(
                                get: { Double(min(refreshInterval, Constants.maxRefreshInterval)) },
                                set: { refreshInterval = max(Constants.minRefreshInterval, Int($0)) }
                            ), in: Double(Constants.minRefreshInterval)...Double(Constants.maxRefreshInterval), step: Double(Constants.refreshIntervalStep))

                            TextField("", value: $refreshInterval, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 55)
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    if refreshInterval < Constants.minRefreshInterval {
                                        refreshInterval = Constants.minRefreshInterval
                                    }
                                }

                            Text("s")
                                .foregroundColor(.secondary)
                        }

                        Text("How often to check for PR status updates")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        Toggle("Quiet hours", isOn: $enableQuietHours)
                            .help("Pause auto refresh during specified hours")

                        if enableQuietHours {
                            HStack(spacing: 8) {
                                Text("Pause from")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Picker("", selection: $quietHoursStart) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Text(String(format: "%02d:00", hour)).tag(hour)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 80)
                                Text("to")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Picker("", selection: $quietHoursEnd) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Text(String(format: "%02d:00", hour)).tag(hour)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 80)
                            }

                            Toggle("Also pause on weekends", isOn: $quietHoursSkipWeekends)

                            Text("Auto refresh is paused during quiet hours. You can still refresh manually.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
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

            Section("Inactive Branch Detection") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable inactive branch detection", isOn: $enableInactiveBranchDetection)
                        .help("Highlight PRs that haven't been updated in a while")

                    if enableInactiveBranchDetection {
                        Stepper("Days without update: \(inactiveBranchThresholdDays)",
                                value: $inactiveBranchThresholdDays,
                                in: Constants.minInactiveBranchThreshold...Constants.maxInactiveBranchThreshold)
                            .padding(.top, 4)

                        Toggle("Hide inactive PRs", isOn: $hideInactivePRs)
                            .help("Completely hide PRs that are inactive instead of just marking them")

                        Text("PRs not updated for \(inactiveBranchThresholdDays) days will \(hideInactivePRs ? "be hidden" : "show as inactive")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Keep as floating window", isOn: $useFloatingWindow)
                        .help("Show MonitorLizard as a floating window instead of a menu bar dropdown")
                        .onChange(of: useFloatingWindow) { _, newValue in
                            if !newValue {
                                WindowManager.shared.destroyFloatingWindow()
                            }
                        }

                    Text("Show as a draggable floating window. Close the window to return to menu bar mode.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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

    // MARK: - Users

    @State private var selectedSettingsUserId: String?
    @State private var showAddUser = false
    @State private var newUsername = ""
    @State private var newDisplayName = ""
    @State private var newIgnoredRepo = ""
    @State private var newCheckPattern = ""
    @State private var newCheckRepo = "*"

    private var selectedSettingsUser: MonitoredUser? {
        guard let selectedSettingsUserId,
              selectedSettingsUserId != Self.globalRulesSelectionId else { return nil }
        return monitoredUsersService.users.first { $0.id.uuidString == selectedSettingsUserId }
    }

    private var isGlobalRulesSelected: Bool {
        selectedSettingsUserId == Self.globalRulesSelectionId
    }

    private var globalIgnoredRepos: [String] {
        get { decodeGlobalRepos() }
        nonmutating set { saveGlobalRepos(newValue) }
    }

    private var globalIgnoredChecks: [IgnoredCheckRule] {
        get { decodeGlobalChecks() }
        nonmutating set { saveGlobalChecks(newValue) }
    }

    private var usersSettings: some View {
        HSplitView {
            // Left: user list
            VStack(spacing: 0) {
                List(selection: $selectedSettingsUserId) {
                    HStack {
                        Text("global_rules")
                    }
                    .tag(Self.globalRulesSelectionId)

                    ForEach(monitoredUsersService.users) { user in
                        HStack {
                            Text(user.label)
                            if user.isMe {
                                Text("(you)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(user.id.uuidString)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Button(action: { showAddUser = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("Add a GitHub user to monitor")

                    Button(action: {
                        if let id = selectedSettingsUserId,
                           let uuid = UUID(uuidString: id) {
                            monitoredUsersService.removeUser(id: uuid)
                            selectedSettingsUserId = monitoredUsersService.users.first?.id
                                .uuidString ?? Self.globalRulesSelectionId
                        }
                    }) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedSettingsUser?.isMe == true || isGlobalRulesSelected || selectedSettingsUserId == nil)
                    .help("Remove selected user")

                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 140, maxWidth: 180)

            // Right: selected user config
            if isGlobalRulesSelected {
                globalRulesDetailView
            } else if let user = selectedSettingsUser {
                userDetailView(user: user)
            } else {
                Text("Select a user")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selectedSettingsUserId == nil {
                selectedSettingsUserId = Self.globalRulesSelectionId
            }
        }
        .sheet(isPresented: $showAddUser) {
            addUserSheet
        }
    }

    private func userDetailView(user: MonitoredUser) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Username
                VStack(alignment: .leading, spacing: 4) {
                    Text("Username")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if user.isMe {
                        Text("@me (authenticated user)")
                            .font(.body)
                    } else {
                        Text(user.username)
                            .font(.body)
                    }
                }

                // Display Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Display Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Optional label for tab", text: Binding(
                        get: { user.displayName ?? "" },
                        set: { newValue in
                            var updated = user
                            updated.displayName = newValue.isEmpty ? nil : newValue
                            monitoredUsersService.updateUser(updated)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                Divider()

                // Ignored Repositories
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ignored Repositories")
                        .font(.headline)
                    Text("PRs from these repos won't be shown.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(Array(user.ignoredRepos.enumerated()), id: \.offset) { index, repo in
                        HStack {
                            TextField("owner/repo", text: Binding(
                                get: { repo },
                                set: { newValue in
                                    var updated = user
                                    updated.ignoredRepos[index] = newValue
                                    monitoredUsersService.updateUser(updated)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                            Button(action: {
                                var updated = user
                                updated.ignoredRepos.remove(at: index)
                                monitoredUsersService.updateUser(updated)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        TextField("owner/repo", text: $newIgnoredRepo)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addIgnoredRepo(for: user) }
                        Button("Add") { addIgnoredRepo(for: user) }
                            .disabled(newIgnoredRepo.isEmpty)
                    }
                }

                Divider()

                // Ignored CI Checks
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ignored CI Checks")
                        .font(.headline)
                    Text("Failing checks matching these patterns are excluded from status calculation. Supports * wildcard.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(Array(user.ignoredChecks.enumerated()), id: \.element.id) { index, rule in
                        HStack {
                            TextField("Pattern", text: Binding(
                                get: { rule.pattern },
                                set: { newValue in
                                    var updated = user
                                    updated.ignoredChecks[index].pattern = newValue
                                    monitoredUsersService.updateUser(updated)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                            TextField("Repo", text: Binding(
                                get: { rule.repository },
                                set: { newValue in
                                    var updated = user
                                    updated.ignoredChecks[index].repository = newValue.isEmpty ? "*" : newValue
                                    monitoredUsersService.updateUser(updated)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 140)
                            Button(action: {
                                var updated = user
                                updated.ignoredChecks.remove(at: index)
                                monitoredUsersService.updateUser(updated)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        TextField("Pattern (e.g. codecov/*)", text: $newCheckPattern)
                            .textFieldStyle(.roundedBorder)
                        TextField("Repo (* for all)", text: $newCheckRepo)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        Button("Add") { addIgnoredCheck(for: user) }
                            .disabled(newCheckPattern.isEmpty)
                    }
                }
            }
            .padding()
        }
    }

    private var globalRulesDetailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("global_rules")
                        .font(.headline)
                    Text("These ignore rules apply to all monitored users. This item only exists in Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ignored Repositories")
                        .font(.headline)
                    Text("PRs from these repos won't be shown for any user.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(Array(globalIgnoredRepos.enumerated()), id: \.offset) { index, repo in
                        HStack {
                            TextField("owner/repo", text: Binding(
                                get: { globalIgnoredRepos[index] },
                                set: { newValue in
                                    var updated = globalIgnoredRepos
                                    updated[index] = newValue
                                    globalIgnoredRepos = updated
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                            Button(action: {
                                var updated = globalIgnoredRepos
                                updated.remove(at: index)
                                globalIgnoredRepos = updated
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        TextField("owner/repo", text: $newIgnoredRepo)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addGlobalIgnoredRepo() }
                        Button("Add") { addGlobalIgnoredRepo() }
                            .disabled(newIgnoredRepo.isEmpty)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ignored CI Checks")
                        .font(.headline)
                    Text("Failing checks matching these patterns are excluded from status calculation for all users. Supports * wildcard.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(Array(globalIgnoredChecks.enumerated()), id: \.element.id) { index, rule in
                        HStack {
                            TextField("Pattern", text: Binding(
                                get: { rule.pattern },
                                set: { newValue in
                                    var updated = globalIgnoredChecks
                                    updated[index].pattern = newValue
                                    globalIgnoredChecks = updated
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                            TextField("Repo", text: Binding(
                                get: { rule.repository },
                                set: { newValue in
                                    var updated = globalIgnoredChecks
                                    updated[index].repository = newValue.isEmpty ? "*" : newValue
                                    globalIgnoredChecks = updated
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 140)
                            Button(action: {
                                var updated = globalIgnoredChecks
                                updated.remove(at: index)
                                globalIgnoredChecks = updated
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        TextField("Pattern (e.g. codecov/*)", text: $newCheckPattern)
                            .textFieldStyle(.roundedBorder)
                        TextField("Repo (* for all)", text: $newCheckRepo)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        Button("Add") { addGlobalIgnoredCheck() }
                            .disabled(newCheckPattern.isEmpty)
                    }
                }
            }
            .padding()
        }
    }

    private func submitAddUser() {
        let username = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else { return }
        monitoredUsersService.addUser(
            username: username,
            displayName: newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        newUsername = ""
        newDisplayName = ""
        showAddUser = false
    }

    private var addUserSheet: some View {
        VStack(spacing: 12) {
            Text("Add Monitored User")
                .font(.headline)
            TextField("GitHub username", text: $newUsername)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitAddUser() }
            TextField("Display name (optional)", text: $newDisplayName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitAddUser() }
            HStack {
                Spacer()
                Button("Cancel") { showAddUser = false }
                Button("Add") { submitAddUser() }
                    .disabled(newUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func addIgnoredRepo(for user: MonitoredUser) {
        let repo = newIgnoredRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty else { return }
        var updated = user
        guard !updated.ignoredRepos.contains(repo) else { newIgnoredRepo = ""; return }
        updated.ignoredRepos.append(repo)
        monitoredUsersService.updateUser(updated)
        newIgnoredRepo = ""
    }

    private func addIgnoredCheck(for user: MonitoredUser) {
        let pattern = newCheckPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        var updated = user
        let repoScope = newCheckRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = IgnoredCheckRule(pattern: pattern, repository: repoScope.isEmpty ? "*" : repoScope)
        updated.ignoredChecks.append(rule)
        monitoredUsersService.updateUser(updated)
        newCheckPattern = ""
        newCheckRepo = "*"
    }

    private func addGlobalIgnoredRepo() {
        let repo = newIgnoredRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty else { return }
        var updated = globalIgnoredRepos
        guard !updated.contains(repo) else { newIgnoredRepo = ""; return }
        updated.append(repo)
        globalIgnoredRepos = updated
        newIgnoredRepo = ""
    }

    private func addGlobalIgnoredCheck() {
        let pattern = newCheckPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        var updated = globalIgnoredChecks
        let repoScope = newCheckRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = IgnoredCheckRule(pattern: pattern, repository: repoScope.isEmpty ? "*" : repoScope)
        updated.append(rule)
        globalIgnoredChecks = updated
        newCheckPattern = ""
        newCheckRepo = "*"
    }

    private func decodeGlobalRepos() -> [String] {
        guard !globalIgnoredReposData.isEmpty,
              let repos = try? JSONDecoder().decode([String].self, from: globalIgnoredReposData) else {
            return []
        }
        return repos
    }

    private func saveGlobalRepos(_ repos: [String]) {
        globalIgnoredReposData = (try? JSONEncoder().encode(repos)) ?? Data()
        monitoredUsersService.notifyConfigurationChanged()
    }

    private func decodeGlobalChecks() -> [IgnoredCheckRule] {
        guard !globalIgnoredChecksData.isEmpty,
              let rules = try? JSONDecoder().decode([IgnoredCheckRule].self, from: globalIgnoredChecksData) else {
            return []
        }
        return rules
    }

    private func saveGlobalChecks(_ rules: [IgnoredCheckRule]) {
        globalIgnoredChecksData = (try? JSONEncoder().encode(rules)) ?? Data()
        monitoredUsersService.notifyConfigurationChanged()
    }

    // MARK: - Notifications

    private var notificationSettings: some View {
        Form {
            refreshLogSection

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

    @StateObject private var refreshLogger = RefreshLogger.shared

    private var refreshLogSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Refresh Log")
                        .font(.headline)
                    Spacer()
                    Button("Clear") {
                        refreshLogger.clear()
                    }
                    .font(.caption)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(refreshLogger.logs.isEmpty ? "No logs yet. Logs appear after a refresh." : refreshLogger.logs)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(refreshLogger.logs.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id("logBottom")
                    }
                    .frame(height: 150)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)
                    .onChange(of: refreshLogger.logs) { _, _ in
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - About

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
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
