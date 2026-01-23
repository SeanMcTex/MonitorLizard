import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var viewModel: PRMonitorViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Error message or PR list
            if let error = viewModel.errorMessage {
                errorView(error)
            } else if !viewModel.isGHAvailable {
                ghUnavailableView
            } else if viewModel.isLoading && viewModel.authoredPRs.isEmpty && viewModel.reviewPRs.isEmpty {
                loadingView
            } else if viewModel.authoredPRs.isEmpty && viewModel.reviewPRs.isEmpty && !viewModel.isLoading {
                emptyStateView
            } else {
                prListView
            }

            Divider()

            // Footer
            footerView
        }
        .frame(minWidth: 400, maxWidth: 500)
    }

    private var headerView: some View {
        HStack {
            Text("Pull Requests")
                .font(.headline)

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
        .padding()
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
        .frame(minHeight: 200, maxHeight: 300)
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
        .frame(minHeight: 200, maxHeight: 300)
        .frame(maxWidth: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 50))
                .foregroundColor(.green)

            Text("No Open PRs")
                .font(.headline)

            Text("You don't have any open pull requests at the moment.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(minHeight: 200, maxHeight: 300)
        .frame(maxWidth: .infinity)
    }

    private var loadingView: some View {
        ContentUnavailableView {
            Label("Loading Pull Requests", systemImage: "arrow.circlepath")
        } description: {
            Text("Fetching your open PRs from GitHub...")
        }
        .frame(minHeight: 200, maxHeight: 300)
        .frame(maxWidth: .infinity)
    }

    private var prListView: some View {
        let totalPRs = viewModel.authoredPRs.count + viewModel.reviewPRs.count
        let estimatedRowHeight: CGFloat = 120 // Approximate height per PR row
        let sectionHeaderHeight: CGFloat = 40
        let numSections = (viewModel.authoredPRs.isEmpty ? 0 : 1) + (viewModel.reviewPRs.isEmpty ? 0 : 1)
        let estimatedContentHeight = CGFloat(totalPRs) * estimatedRowHeight + CGFloat(numSections) * sectionHeaderHeight
        let maxHeight = calculateMaxHeight()
        let targetHeight = min(estimatedContentHeight, maxHeight)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Review PRs Section (FIRST - prioritize unblocking teammates)
                    if !viewModel.reviewPRs.isEmpty {
                        sectionHeader(title: "Awaiting My Review", count: viewModel.reviewPRs.count)
                            .id("top")

                        ForEach(viewModel.reviewPRs) { pr in
                            PRRowView(pr: pr)
                                .environmentObject(viewModel)
                            Divider()
                        }
                    }

                    // Authored PRs Section (SECOND)
                    if !viewModel.authoredPRs.isEmpty {
                        sectionHeader(title: "My PRs", count: viewModel.authoredPRs.count)
                            .id(viewModel.reviewPRs.isEmpty ? "top" : nil)

                        ForEach(viewModel.authoredPRs) { pr in
                            PRRowView(pr: pr)
                                .environmentObject(viewModel)
                            Divider()
                        }
                    }
                }
            }
            .frame(height: targetHeight)
            .onAppear {
                proxy.scrollTo("top", anchor: .top)
            }
        }
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
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
        // Get screen height and use 70% of it, max 700px
        if let screen = NSScreen.main {
            let maxHeight = screen.visibleFrame.height * Constants.menuMaxHeightMultiplier
            return min(maxHeight, 700)
        }
        return 600 // Fallback
    }

    private var footerView: some View {
        HStack(spacing: 12) {
            if let lastRefresh = viewModel.lastRefreshTime {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text("Updated \(timeAgo(lastRefresh))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button("Settings") {
                WindowManager.shared.showSettings()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

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
