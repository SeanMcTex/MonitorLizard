import Foundation
import SwiftUI
import Combine

@MainActor
class PRMonitorViewModel: ObservableObject {
    @Published var pullRequests: [PullRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRefreshTime: Date?
    @Published var isGHAvailable = true
    @Published var hasFailingBuilds = false

    private let githubService = GitHubService()
    private let watchlistService = WatchlistService.shared
    private let notificationService = NotificationService.shared

    private var refreshTimer: Timer?
    private var sortSettingObserver: AnyCancellable?
    private var unsortedPullRequests: [PullRequest] = []

    @AppStorage("refreshInterval") private var refreshInterval: Int = 30
    @AppStorage("sortNonSuccessFirst") private var sortNonSuccessFirst: Bool = false

    init() {
        setupNotifications()
        startPolling()
        observeSortSetting()
    }

    private func observeSortSetting() {
        sortSettingObserver = UserDefaults.standard
            .publisher(for: \.sortNonSuccessFirst)
            .dropFirst() // Skip initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySorting()
            }
    }

    func startPolling() {
        // Cancel existing timer
        refreshTimer?.invalidate()

        // Create new timer
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(refreshInterval),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }

        // Initial fetch
        Task {
            await checkGHAvailability()
            if isGHAvailable {
                await refresh()
            }
        }
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func updateRefreshInterval(_ interval: Int) {
        refreshInterval = interval
        startPolling() // Restart timer with new interval
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch all open PRs with their statuses
            let fetchedPRs = try await githubService.fetchAllOpenPRs()

            // Check for watched PR completions
            let completed = watchlistService.checkForCompletions(currentPRs: fetchedPRs)

            // Send notifications for completed builds
            for pr in completed {
                notificationService.notifyBuildComplete(pr: pr, status: pr.buildStatus)
            }

            // Update PRs with watch status
            unsortedPullRequests = fetchedPRs.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            }

            // Apply sorting
            applySorting()

            // Update failure indicator
            hasFailingBuilds = pullRequests.contains { $0.buildStatus == .failure || $0.buildStatus == .error }

            lastRefreshTime = Date()
            isGHAvailable = true

        } catch let error as GitHubError {
            print("GitHubError: \(error)")
            errorMessage = error.localizedDescription
            if error == .notInstalled || error == .notAuthenticated {
                isGHAvailable = false
            }
        } catch let error as ShellError {
            print("ShellError: \(error)")
            errorMessage = error.localizedDescription
        } catch let error as DecodingError {
            print("DecodingError: \(error)")
            errorMessage = "Failed to parse GitHub data. Please try again."
        } catch {
            print("Unknown error: \(error)")
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func applySorting() {
        if sortNonSuccessFirst {
            // Sort with non-success first
            pullRequests = unsortedPullRequests.sorted { pr1, pr2 in
                let pr1Success = pr1.buildStatus == .success
                let pr2Success = pr2.buildStatus == .success

                // If one is success and other isn't, non-success comes first
                if pr1Success != pr2Success {
                    return !pr1Success
                }

                // Otherwise maintain original order
                return false
            }
        } else {
            // Restore original order from GitHub
            pullRequests = unsortedPullRequests
        }

        // Update failure indicator
        hasFailingBuilds = pullRequests.contains { $0.buildStatus == .failure || $0.buildStatus == .error }
    }

    func toggleWatch(for pr: PullRequest) {
        if watchlistService.isWatched(pr) {
            watchlistService.unwatch(pr)
        } else {
            watchlistService.watch(pr)
        }

        // Update both arrays
        if let index = unsortedPullRequests.firstIndex(where: { $0.id == pr.id }) {
            unsortedPullRequests[index].isWatched.toggle()
        }
        if let index = pullRequests.firstIndex(where: { $0.id == pr.id }) {
            pullRequests[index].isWatched.toggle()
        }
    }

    func clearAllWatched() {
        watchlistService.clearAll()
        // Update all PRs to unwatched state in both arrays
        unsortedPullRequests = unsortedPullRequests.map { pr in
            var updated = pr
            updated.isWatched = false
            return updated
        }
        pullRequests = pullRequests.map { pr in
            var updated = pr
            updated.isWatched = false
            return updated
        }
    }

    private func checkGHAvailability() async {
        do {
            try await githubService.checkGHAvailable()
            isGHAvailable = true
            errorMessage = nil
        } catch let error as GitHubError {
            isGHAvailable = false
            errorMessage = error.localizedDescription
        } catch {
            isGHAvailable = false
            errorMessage = "Failed to check GitHub CLI availability"
        }
    }

    private func setupNotifications() {
        Task {
            try? await notificationService.requestAuthorization()
        }
    }
}

// Extension to make UserDefaults key observable
extension UserDefaults {
    @objc dynamic var sortNonSuccessFirst: Bool {
        return bool(forKey: "sortNonSuccessFirst")
    }
}
