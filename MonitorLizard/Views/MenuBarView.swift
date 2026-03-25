import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var viewModel: PRMonitorViewModel
    @State private var isWindowVisible = true

    var body: some View {
        ZStack {
            WindowOcclusionObserver { visible in
                isWindowVisible = visible
            }
            .frame(width: 0, height: 0)

            if isWindowVisible {
                contentView
            }
        }
    }

    private var isFloating: Bool {
        WindowManager.shared.isFloatingMode
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Error message or PR list
            if let error = viewModel.errorMessage {
                errorView(error)
            } else if !viewModel.isGHAvailable {
                ghUnavailableView
            } else if viewModel.isLoading && viewModel.authoredPRs.isEmpty && viewModel.reviewPRs.isEmpty && viewModel.otherPullRequests.isEmpty {
                loadingView
            } else if viewModel.authoredPRs.isEmpty && viewModel.reviewPRs.isEmpty && viewModel.filteredOtherPRs.isEmpty && !viewModel.isLoading {
                emptyStateView
            } else {
                prListView
            }

            Divider()

            // Footer
            footerView
        }
        .frame(
            minWidth: 400,
            maxWidth: isFloating ? .infinity : 500,
            maxHeight: isFloating ? .infinity : nil
        )
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            // User segment control (only if multiple users)
            if viewModel.monitoredUsers.count > 1 {
                HStack(spacing: 2) {
                    ForEach(viewModel.monitoredUsers) { user in
                        Button(action: { viewModel.selectUser(id: user.id) }) {
                            HStack(spacing: 4) {
                                if let color = viewModel.userStatus(for: user.id) {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 6, height: 6)
                                }
                                Text(user.label)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                viewModel.selectedUser?.id == user.id
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear
                            )
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Repo picker row
            HStack {
                Text("Pull Requests for")
                    .font(.headline)

                Picker("", selection: $viewModel.selectedRepository) {
                    Text("All Repositories").tag("All Repositories")
                    Divider()
                    ForEach(viewModel.availableRepositories, id: \.self) { repo in
                        Text(repo.split(separator: "/").last.map(String.init) ?? repo).tag(repo)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20, height: 20)
                } else {
                    Button(action: {
                        Task {
                            await viewModel.refresh()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh now")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, viewModel.monitoredUsers.count > 1 ? 4 : 0)
        }
        .padding(.top, viewModel.monitoredUsers.count > 1 ? 0 : 12)
        .padding(.bottom, 8)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text(error)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            if !viewModel.isGHAvailable {
                Button("Open GitHub CLI Website") {
                    if let url = URL(string: "https://cli.github.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Button("Retry") {
                Task {
                    await viewModel.refresh()
                }
            }
        }
        .frame(minHeight: 200, maxHeight: isFloating ? .infinity : 300)
        .frame(maxWidth: .infinity)
    }

    private var ghUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 50))
                .foregroundColor(.gray)

            Text("GitHub CLI Required")
                .font(.headline)

            Text("Please install and authenticate the GitHub CLI (gh)")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Install Instructions") {
                if let url = URL(string: "https://cli.github.com") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .frame(minHeight: 200, maxHeight: isFloating ? .infinity : 300)
        .frame(maxWidth: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 50))
                .foregroundColor(.green)

            Text("No Open PRs")
                .font(.headline)

            Text("No open pull requests found.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(minHeight: 200, maxHeight: isFloating ? .infinity : 300)
        .frame(maxWidth: .infinity)
    }

    private var loadingView: some View {
        ContentUnavailableView {
            Label("Loading Pull Requests", systemImage: "arrow.circlepath")
        } description: {
            Text("Fetching open PRs from GitHub...")
        }
        .frame(minHeight: 200, maxHeight: isFloating ? .infinity : 300)
        .frame(maxWidth: .infinity)
    }

    private var prListView: some View {
        let totalPRs = viewModel.authoredPRs.count + viewModel.reviewPRs.count + viewModel.filteredOtherPRs.count
        let estimatedRowHeight: CGFloat = 120
        let sectionHeaderHeight: CGFloat = 40
        let showReview = viewModel.selectedUser?.isMe == true && !viewModel.reviewPRs.isEmpty
        let numSections = (showReview ? 1 : 0)
            + (viewModel.authoredPRs.isEmpty ? 0 : 1)
            + (viewModel.filteredOtherPRs.isEmpty ? 0 : 1)
        let estimatedContentHeight = CGFloat(totalPRs) * estimatedRowHeight + CGFloat(numSections) * sectionHeaderHeight
        let maxHeight = calculateMaxHeight()
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("top")

                    // Review PRs Section (only for @me)
                    if showReview {
                        sectionHeader(type: .reviewing, count: viewModel.reviewPRs.count, username: nil)
                            .id("header-review")

                        ForEach(viewModel.reviewPRs) { pr in
                            PRRowView(pr: pr)
                                .environmentObject(viewModel)
                                .id("review-\(pr.id)")
                            Divider()
                        }
                    }

                    // Other PRs Section
                    if !viewModel.filteredOtherPRs.isEmpty {
                        sectionHeader(type: .other, count: viewModel.filteredOtherPRs.count, username: nil)
                            .id("header-other")

                        ForEach(viewModel.filteredOtherPRs) { pr in
                            PRRowView(pr: pr)
                                .environmentObject(viewModel)
                                .id("other-\(pr.id)")
                            Divider()
                        }
                    }

                    // Authored PRs Section
                    if !viewModel.authoredPRs.isEmpty {
                        sectionHeader(type: .authored, count: viewModel.authoredPRs.count, username: viewModel.selectedUser?.username)
                            .id("header-authored")

                        ForEach(viewModel.authoredPRs) { pr in
                            PRRowView(pr: pr)
                                .environmentObject(viewModel)
                                .id("authored-\(pr.id)")
                            Divider()
                        }
                    }
                }
            }
            .frame(height: isFloating ? nil : min(estimatedContentHeight, maxHeight))
            .frame(maxHeight: isFloating ? .infinity : nil)
            .id(viewModel.selectedRepository)
            .onAppear {
                proxy.scrollTo("top", anchor: .top)
            }
        }
    }

    private func sectionHeader(type: PRType, count: Int, username: String?) -> some View {
        HStack {
            Text(type.displayTitle(count: count, username: username))
                .font(.headline)
                .foregroundColor(.primary)

            Text("(\(count))")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.05))
    }

    private func calculateMaxHeight() -> CGFloat {
        if let screen = NSScreen.main {
            let maxHeight = screen.visibleFrame.height * Constants.menuMaxHeightMultiplier
            return min(maxHeight, 700)
        }
        return 600
    }

    private var footerView: some View {
        HStack(spacing: 12) {
            if let lastRefresh = viewModel.lastRefreshTime {
                Text("Updated \(timeAgo(lastRefresh))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Menu {
                Button("Add PR...") {
                    WindowManager.shared.showAddPR(viewModel: viewModel)
                }

                Divider()

                if WindowManager.shared.isFloatingMode {
                    Button("Attach to Menu Bar") {
                        WindowManager.shared.destroyFloatingWindow()
                    }
                } else {
                    Button("Detach as Floating Window") {
                        WindowManager.shared.showFloatingWindow(viewModel: viewModel)
                    }
                }

                Divider()

                Button("Settings") {
                    WindowManager.shared.showSettings()
                }

                Button("Check for Updates...") {
                    UpdateService.shared.checkForUpdates()
                }
                .disabled(!UpdateService.shared.canCheckForUpdates)
            } label: {
                Label("Commands", systemImage: "gearshape")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding()
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))

        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours)h ago"
        } else {
            let days = seconds / 86400
            return "\(days)d ago"
        }
    }
}

struct WindowOcclusionObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        TrackingView(onChange: onChange)
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onChange = onChange
    }

    class TrackingView: NSView {
        var onChange: (Bool) -> Void
        private var observer: NSObjectProtocol?
        private var occlusionObserver: NSObjectProtocol?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map { NotificationCenter.default.removeObserver($0) }
            occlusionObserver.map { NotificationCenter.default.removeObserver($0) }
            observer = nil
            occlusionObserver = nil
            guard let window else { return }

            let becomeKey = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in self?.onChange(true) }

            let occlusion = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak window, weak self] _ in
                guard let window, let self else { return }
                if !window.occlusionState.contains(.visible) {
                    self.onChange(false)
                }
            }

            observer = becomeKey
            occlusionObserver = occlusion
        }

        deinit {
            observer.map { NotificationCenter.default.removeObserver($0) }
            occlusionObserver.map { NotificationCenter.default.removeObserver($0) }
        }
    }
}
