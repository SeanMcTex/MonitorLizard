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
            } else if viewModel.pullRequests.isEmpty && !viewModel.isLoading {
                emptyStateView
            } else {
                prListView
            }

            Divider()

            // Footer
            footerView
        }
        .frame(width: 400)
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
        .frame(height: 300)
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
        .frame(height: 300)
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
        .frame(height: 300)
    }

    private var prListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.pullRequests) { pr in
                    PRRowView(pr: pr)
                        .environmentObject(viewModel)
                    Divider()
                }
            }
        }
        .frame(height: calculateMaxHeight())
    }

    private func calculateMaxHeight() -> CGFloat {
        // Get screen height and use 70% of it, max 700px
        if let screen = NSScreen.main {
            let maxHeight = screen.visibleFrame.height * 0.7
            return min(maxHeight, 700)
        }
        return 600 // Fallback
    }

    private var footerView: some View {
        HStack(spacing: 12) {
            if let lastRefresh = viewModel.lastRefreshTime {
                Text("Updated \(timeAgo(lastRefresh))")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
