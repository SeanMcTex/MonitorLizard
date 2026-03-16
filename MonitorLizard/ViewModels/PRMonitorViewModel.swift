import Foundation
import SwiftUI
import Combine

enum OtherPRError: LocalizedError {
    case invalidURL
    case alreadyAdded
    case alreadyTracked
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid GitHub PR URL. Expected format: https://github.com/owner/repo/pull/123"
        case .alreadyAdded: return "This PR is already in Other PRs"
        case .alreadyTracked: return "This PR is already in your authored or review list"
        case .notFound: return "PR not found or not accessible"
        }
    }
}

@MainActor
class PRMonitorViewModel: ObservableObject {
    @Published var pullRequests: [PullRequest] = []
    @Published var otherPullRequests: [PullRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRefreshTime: Date?
    @Published var isGHAvailable = true
    @Published var showWarningIcon = false
    @AppStorage("selectedRepository") var selectedRepository: String = "All Repositories"

    private let githubService: GitHubService
    private let isDemoMode: Bool
    private let watchlistService = WatchlistService.shared
    private let notificationService = NotificationService.shared
    private let otherPRsService = OtherPRsService()

    private var refreshTimer: Timer?
    private var sortSettingObserver: AnyCancellable?
    private var reviewPRsSettingObserver: AnyCancellable?
    private var unsortedPullRequests: [PullRequest] = []

    @AppStorage("refreshInterval") private var refreshInterval: Int = Constants.defaultRefreshInterval
    @AppStorage("sortNonSuccessFirst") private var sortNonSuccessFirst: Bool = false
    @AppStorage("enableInactiveBranchDetection") private var enableInactiveBranchDetection: Bool = false
    @AppStorage("inactiveBranchThresholdDays") private var inactiveBranchThresholdDays: Int = Constants.defaultInactiveBranchThreshold
    @AppStorage("showReviewPRs") private var showReviewPRs: Bool = true

    // Computed property for available repositories
    var availableRepositories: [String] {
        let mainRepos = Set(unsortedPullRequests.map { $0.repository.nameWithOwner })
        let otherRepos = Set(otherPullRequests.map { $0.repository.nameWithOwner })
        return mainRepos.union(otherRepos).sorted()
    }

    // Computed properties for filtering PRs by type and repository
    var authoredPRs: [PullRequest] {
        pullRequests.filter { $0.type == .authored }
            .filter { selectedRepository == "All Repositories" || $0.repository.nameWithOwner == selectedRepository }
    }

    var reviewPRs: [PullRequest] {
        guard showReviewPRs else { return [] }
        return pullRequests.filter { $0.type == .reviewing }
            .filter { selectedRepository == "All Repositories" || $0.repository.nameWithOwner == selectedRepository }
    }

    init(isDemoMode: Bool = false) {
        self.isDemoMode = isDemoMode
        self.githubService = GitHubService(isDemoMode: isDemoMode)
        setupNotifications()
        startPolling()
        observeSortSetting()
        observeReviewPRsSetting()
    }

    deinit {
        // Timer invalidation is safe to call synchronously from deinit
        refreshTimer?.invalidate()
        sortSettingObserver?.cancel()
        reviewPRsSettingObserver?.cancel()
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

    private func observeReviewPRsSetting() {
        reviewPRsSettingObserver = UserDefaults.standard
            .publisher(for: \.showReviewPRs)
            .dropFirst() // Skip initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
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
        // Note: We skip checkGHAvailability() here because gh auth status can give misleading
        // errors when offline (reports "token is invalid" instead of network error).
        // Instead, we let the actual PR fetch determine if there's a network or auth issue.
        Task {
            await refresh()
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

        // Start both fetches concurrently
        async let mainFetchTask = githubService.fetchAllOpenPRs(
            enableInactiveDetection: enableInactiveBranchDetection,
            inactiveThresholdDays: inactiveBranchThresholdDays,
            isDemoMode: isDemoMode
        )
        async let otherFetchTask = fetchAllOtherPRs()

        do {
            let fetchResult = try await mainFetchTask
            let fetchedOther = await otherFetchTask
            let fetchedPRs = fetchResult.pullRequests

            // Deduplicate: remove from main list any PR that's also in Other PRs
            let otherIDs = Set(fetchedOther.map { $0.id })
            let dedupedPRs = fetchedPRs.filter { !otherIDs.contains($0.id) }

            // Check for watched PR completions across all PRs
            let completed = watchlistService.checkForCompletions(currentPRs: dedupedPRs + fetchedOther)

            // Send notifications for completed builds
            for pr in completed {
                notificationService.notifyBuildComplete(pr: pr, status: pr.buildStatus)
            }

            // Update PRs with watch status
            unsortedPullRequests = dedupedPRs.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            }

            otherPullRequests = fetchedOther.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            }

            // Apply sorting (also updates warning icon)
            applySorting()

            // Reset filter if the selected repo no longer exists, but only when
            // we have a complete result set. Partial results (one fetch failed)
            // may be missing repos that still have open PRs.
            if !fetchResult.isPartial &&
                selectedRepository != "All Repositories" &&
                !unsortedPullRequests.contains(where: { $0.repository.nameWithOwner == selectedRepository }) &&
                !otherPullRequests.contains(where: { $0.repository.nameWithOwner == selectedRepository }) {
                selectedRepository = "All Repositories"
            }

            lastRefreshTime = Date()
            isGHAvailable = true

        } catch let error as GitHubError {
            print("GitHubError: \(error)")
            errorMessage = error.localizedDescription
            // Only mark as unavailable for installation/auth issues, not network errors
            if error == .notInstalled || error == .notAuthenticated {
                isGHAvailable = false
            }
            // Still update Other PRs even if main fetch failed
            let fetchedOther = await otherFetchTask
            otherPullRequests = fetchedOther.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            }
        } catch let error as ShellError {
            print("ShellError: \(error)")
            errorMessage = error.localizedDescription
            let fetchedOther = await otherFetchTask
            otherPullRequests = fetchedOther.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            }
        } catch let error as DecodingError {
            print("DecodingError: \(error)")
            errorMessage = "Failed to parse GitHub data. Please try again."
            let fetchedOther = await otherFetchTask
            otherPullRequests = fetchedOther.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            }
        } catch {
            print("Unknown error: \(error)")
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
            let fetchedOther = await otherFetchTask
            otherPullRequests = fetchedOther.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            }
        }

        isLoading = false
    }

    private func fetchAllOtherPRs() async -> [PullRequest] {
        let ids = otherPRsService.all()
        var results: [PullRequest] = []
        for id in ids {
            if let pr = await githubService.fetchOtherPR(
                id,
                enableInactiveDetection: enableInactiveBranchDetection,
                inactiveThresholdDays: inactiveBranchThresholdDays
            ) {
                results.append(pr)
            }
        }
        return results
    }

    private func applySorting() {
        // Split PRs by type
        let authored = unsortedPullRequests.filter { $0.type == .authored }
        let review = unsortedPullRequests.filter { $0.type == .reviewing }

        // Apply sorting independently within each section
        let sortedAuthored = sortNonSuccessFirst ? sort(authored) : authored
        let sortedReview = sortNonSuccessFirst ? sort(review) : review

        // Concatenate with review PRs first (prioritize unblocking teammates)
        let newPullRequests = sortedReview + sortedAuthored

        // Only update the @Published property if data actually changed, to avoid
        // unnecessary SwiftUI re-renders (which can freeze mid-scroll)
        if newPullRequests != pullRequests {
            pullRequests = newPullRequests
        }

        // Update warning icon indicator (failures, errors, conflicts, changes requested, inactive PRs, or any review PRs)
        let allDisplayed = newPullRequests + otherPullRequests
        let hasBadStatus = allDisplayed.contains { pr in
            let badBuild = pr.buildStatus == .failure || pr.buildStatus == .error
                || pr.buildStatus == .conflict || pr.buildStatus == .inactive
            return badBuild || pr.reviewDecision == .changesRequested
        }
        let hasReviewPRs = newPullRequests.contains { pr in
            pr.type == .reviewing
        }
        showWarningIcon = hasBadStatus || hasReviewPRs
    }

    func addOtherPR(urlString: String) async throws {
        guard let id = GitHubService.parsePRURL(urlString) else {
            throw OtherPRError.invalidURL
        }
        guard !otherPRsService.contains(id) else {
            throw OtherPRError.alreadyAdded
        }
        let normalizedRepo = "\(id.owner)/\(id.repo)".lowercased()
        guard !unsortedPullRequests.contains(where: { pr in
            pr.number == id.number && pr.repository.nameWithOwner.lowercased() == normalizedRepo
        }) else {
            throw OtherPRError.alreadyTracked
        }
        guard let pr = await githubService.fetchOtherPR(
            id,
            enableInactiveDetection: enableInactiveBranchDetection,
            inactiveThresholdDays: inactiveBranchThresholdDays
        ) else {
            throw OtherPRError.notFound
        }
        otherPRsService.add(id)
        var updated = pr
        updated.isWatched = watchlistService.isWatched(pr)
        otherPullRequests.append(updated)
        // Deduplicate from main list if this PR appeared there
        unsortedPullRequests.removeAll { $0.id == pr.id }
        pullRequests.removeAll { $0.id == pr.id }
        applySorting()
    }

    func removeOtherPR(_ pr: PullRequest) {
        let parts = pr.repository.nameWithOwner.split(separator: "/")
        guard parts.count == 2 else { return }
        let id = OtherPRIdentifier(
            host: pr.host,
            owner: String(parts[0]),
            repo: String(parts[1]),
            number: pr.number
        )
        otherPRsService.remove(id)
        otherPullRequests.removeAll { $0.id == pr.id }
        applySorting()
    }

    private func sort(_ prs: [PullRequest]) -> [PullRequest] {
        prs.sorted { pr1, pr2 in
            let nonSuccessStatuses: [BuildStatus] = [.failure, .error, .conflict, .pending, .inactive]
            let pr1NonSuccess = nonSuccessStatuses.contains(pr1.buildStatus) || pr1.reviewDecision == .changesRequested
            let pr2NonSuccess = nonSuccessStatuses.contains(pr2.buildStatus) || pr2.reviewDecision == .changesRequested

            // If one is non-success and other isn't, non-success comes first
            if pr1NonSuccess != pr2NonSuccess {
                return pr1NonSuccess
            }

            // Otherwise maintain original order
            return false
        }
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
        for index in unsortedPullRequests.indices {
            unsortedPullRequests[index].isWatched = false
        }
        for index in pullRequests.indices {
            pullRequests[index].isWatched = false
        }
    }

    private func checkGHAvailability() async {
        do {
            try await githubService.checkGHAvailable()
            isGHAvailable = true
            errorMessage = nil
        } catch let error as GitHubError {
            // Only mark as unavailable for installation/auth issues, not network errors
            if error == .notInstalled || error == .notAuthenticated {
                isGHAvailable = false
            }
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

// Extension to make UserDefaults keys observable
extension UserDefaults {
    @objc dynamic var sortNonSuccessFirst: Bool {
        return bool(forKey: "sortNonSuccessFirst")
    }

    @objc dynamic var showReviewPRs: Bool {
        return bool(forKey: "showReviewPRs")
    }
}
