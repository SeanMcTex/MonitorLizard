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

struct PerUserPRCache {
    var rawPRs: [PullRequest] = []       // Before ignored repos/checks filtering
    var unsortedPRs: [PullRequest] = []  // After filtering, before sorting
    var hasFailure: Bool = false
    var hasPending: Bool = false
}

@MainActor
class PRMonitorViewModel: ObservableObject {
    private enum GlobalRulesDefaults {
        static let ignoredReposKey = "globalIgnoredReposData"
        static let ignoredChecksKey = "globalIgnoredChecksData"
    }

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
    private let watchlistService: WatchlistService
    private let notificationService = NotificationService.shared
    private let otherPRsService: OtherPRsService
    private let customNamesService: CustomNamesService
    let monitoredUsersService: MonitoredUsersService
    private let prCacheService: PRCacheService

    private var refreshTimer: Timer?
    private var sortSettingObserver: AnyCancellable?
    private var reviewPRsSettingObserver: AnyCancellable?
    private var monitoredUsersObserver: AnyCancellable?
    private var unsortedPullRequests: [PullRequest] = []
    private var perUserCache: [UUID: PerUserPRCache] = [:]

    @AppStorage("refreshInterval") private var refreshInterval: Int = Constants.defaultRefreshInterval
    @AppStorage("disableAutoRefresh") private var disableAutoRefresh: Bool = false
    @AppStorage("refreshOnStartup") private var refreshOnStartup: Bool = true
    @AppStorage("enableQuietHours") private var enableQuietHours: Bool = false
    @AppStorage("quietHoursStart") private var quietHoursStart: Int = Constants.defaultQuietHoursStart
    @AppStorage("quietHoursEnd") private var quietHoursEnd: Int = Constants.defaultQuietHoursEnd
    @AppStorage("quietHoursSkipWeekends") private var quietHoursSkipWeekends: Bool = true
    @AppStorage("sortNonSuccessFirst") private var sortNonSuccessFirst: Bool = false
    @AppStorage("enableInactiveBranchDetection") private var enableInactiveBranchDetection: Bool = false
    @AppStorage("inactiveBranchThresholdDays") private var inactiveBranchThresholdDays: Int = Constants.defaultInactiveBranchThreshold
    @AppStorage("showReviewPRs") private var showReviewPRs: Bool = true

    // MARK: - Computed Properties

    var availableRepositories: [String] {
        let mainRepos = Set(unsortedPullRequests.map { $0.repository.nameWithOwner })
        let otherRepos = Set(otherPullRequests.map { $0.repository.nameWithOwner })
        return mainRepos.union(otherRepos).sorted()
    }

    var authoredPRs: [PullRequest] {
        pullRequests.filter { $0.type == .authored }
            .filter { selectedRepository == "All Repositories" || $0.repository.nameWithOwner == selectedRepository }
    }

    var reviewPRs: [PullRequest] {
        guard showReviewPRs else { return [] }
        return pullRequests.filter { $0.type == .reviewing }
            .filter { selectedRepository == "All Repositories" || $0.repository.nameWithOwner == selectedRepository }
    }

    var filteredOtherPRs: [PullRequest] {
        otherPullRequests
            .filter { selectedRepository == "All Repositories" || $0.repository.nameWithOwner == selectedRepository }
    }

    var selectedUser: MonitoredUser? {
        monitoredUsersService.selectedUser
    }

    var monitoredUsers: [MonitoredUser] {
        monitoredUsersService.users
    }

    // MARK: - Init

    init(isDemoMode: Bool = false,
         watchlistService: WatchlistService? = nil,
         otherPRsService: OtherPRsService? = nil,
         customNamesService: CustomNamesService? = nil,
         monitoredUsersService: MonitoredUsersService? = nil,
         prCacheService: PRCacheService? = nil) {
        self.isDemoMode = isDemoMode
        self.githubService = GitHubService(isDemoMode: isDemoMode)
        self.watchlistService = watchlistService ?? .shared
        self.otherPRsService = otherPRsService ?? OtherPRsService()
        self.customNamesService = customNamesService ?? CustomNamesService()
        self.monitoredUsersService = monitoredUsersService ?? .shared
        self.prCacheService = prCacheService ?? .shared
        restoreFromCache()
        setupNotifications()
        startPolling()
        observeSortSetting()
        observeReviewPRsSetting()
        observeMonitoredUsers()
        observeRefreshSettings()
        observeHideInactiveSetting()
    }

    deinit {
        refreshTimer?.invalidate()
        sortSettingObserver?.cancel()
        reviewPRsSettingObserver?.cancel()
        monitoredUsersObserver?.cancel()
        usersChangeObserver?.cancel()
        refreshSettingsObserver?.cancel()
    }

    // MARK: - Observers

    private func observeSortSetting() {
        sortSettingObserver = UserDefaults.standard
            .publisher(for: \.sortNonSuccessFirst)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySorting()
            }
    }

    private var hideInactiveObserver: AnyCancellable?

    private func observeHideInactiveSetting() {
        hideInactiveObserver = UserDefaults.standard
            .publisher(for: \.hideInactivePRs)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reapplyFilters()
            }
    }

    private var refreshSettingsObserver: AnyCancellable?

    private func observeRefreshSettings() {
        refreshSettingsObserver = UserDefaults.standard
            .publisher(for: \.disableAutoRefresh)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.startPolling()
            }
    }

    private func observeReviewPRsSetting() {
        reviewPRsSettingObserver = UserDefaults.standard
            .publisher(for: \.showReviewPRs)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    private var usersChangeObserver: AnyCancellable?

    private func observeMonitoredUsers() {
        monitoredUsersObserver = monitoredUsersService.$selectedUserId
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.switchToSelectedUser()
            }
        // Re-apply filters when user configs change (ignored repos/checks)
        usersChangeObserver = monitoredUsersService.$users
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reapplyFilters()
            }
    }

    private func switchToSelectedUser() {
        guard let userId = monitoredUsersService.selectedUserId else { return }
        if let cache = perUserCache[userId] {
            unsortedPullRequests = cache.unsortedPRs
        } else {
            // New user with no cache yet — show empty list
            unsortedPullRequests = []
        }
        selectedRepository = "All Repositories"
        applySorting()
    }

    /// Re-applies ignored repos/checks filters from raw cached data for all users,
    /// then updates the displayed list for the current user.
    private func reapplyFilters() {
        let users = monitoredUsersService.users
        for user in users {
            guard var cache = perUserCache[user.id], !cache.rawPRs.isEmpty else { continue }
            let filtered = filterIgnoredRepos(cache.rawPRs, user: user)
            let withIgnoredChecks = applyIgnoredChecks(filtered, user: user)
            let withInactiveFiltered = filterInactivePRs(withIgnoredChecks)
            cache.unsortedPRs = withInactiveFiltered
            cache.hasFailure = cache.unsortedPRs.contains {
                $0.buildStatus == .failure || $0.buildStatus == .error ||
                $0.buildStatus == .conflict || $0.reviewDecision == .changesRequested
            }
            cache.hasPending = cache.unsortedPRs.contains { $0.buildStatus == .pending }
            perUserCache[user.id] = cache
        }

        // Update displayed list for current user
        let otherIDs = Set(otherPullRequests.map { $0.id })
        if let activeUserId = monitoredUsersService.selectedUserId,
           let cache = perUserCache[activeUserId] {
            unsortedPullRequests = cache.unsortedPRs.filter { !otherIDs.contains($0.id) }
        }
        applySorting()
    }

    // MARK: - User Selection

    func selectUser(id: UUID) {
        monitoredUsersService.selectUser(id: id)
    }

    /// Returns the status color for a user's segment dot.
    func userStatus(for userId: UUID) -> Color? {
        guard let cache = perUserCache[userId] else { return nil }
        if cache.hasFailure { return .red }
        if cache.hasPending { return .orange }
        return .green
    }

    // MARK: - Cache Persistence

    private func restoreFromCache() {
        let cached = prCacheService.loadPerUserCache()
        guard !cached.isEmpty else { return }

        for (userId, data) in cached {
            var cache = PerUserPRCache()
            cache.rawPRs = data.rawPRs
            cache.unsortedPRs = data.unsortedPRs
            cache.hasFailure = data.unsortedPRs.contains {
                $0.buildStatus == .failure || $0.buildStatus == .error ||
                $0.buildStatus == .conflict || $0.reviewDecision == .changesRequested
            }
            cache.hasPending = data.unsortedPRs.contains { $0.buildStatus == .pending }
            perUserCache[userId] = cache
        }

        let cachedOther = prCacheService.loadOtherPRs()
        if !cachedOther.isEmpty {
            otherPullRequests = cachedOther
        }

        // Re-apply all filters (ignored repos/checks, inactive hiding)
        // so settings changed since last persist take effect immediately.
        reapplyFilters()
        if !unsortedPullRequests.isEmpty || !otherPullRequests.isEmpty {
            lastRefreshTime = Date()
        }
    }

    private func persistCache() {
        let saveable = perUserCache.reduce(into: [UUID: (raw: [PullRequest], filtered: [PullRequest])]()) { dict, entry in
            dict[entry.key] = (raw: entry.value.rawPRs, filtered: entry.value.unsortedPRs)
        }
        prCacheService.save(perUserCache: saveable, otherPRs: otherPullRequests)
    }

    // MARK: - Polling

    private var hasStartedOnce = false

    func startPolling() {
        refreshTimer?.invalidate()

        let isInitialStart = !hasStartedOnce
        hasStartedOnce = true
        let hasCache = !unsortedPullRequests.isEmpty || !otherPullRequests.isEmpty

        guard !disableAutoRefresh else {
            if !hasCache {
                Task { await refresh() }
            }
            return
        }

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(refreshInterval),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isInQuietHours() else { return }
                await self.refresh()
            }
        }

        // Decide whether to refresh immediately on startup
        if isInitialStart && !refreshOnStartup && hasCache {
            // Skip initial refresh — use cache, wait for timer
        } else {
            Task { await refresh() }
        }
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func updateRefreshInterval(_ interval: Int) {
        refreshInterval = interval
        startPolling()
    }

    private func isInQuietHours() -> Bool {
        guard enableQuietHours else { return false }

        let now = Calendar.current.dateComponents([.hour, .weekday], from: Date())
        guard let hour = now.hour, let weekday = now.weekday else { return false }

        // weekday: 1 = Sunday, 7 = Saturday
        if quietHoursSkipWeekends && (weekday == 1 || weekday == 7) {
            return true
        }

        let start = quietHoursStart
        let end = quietHoursEnd

        if start < end {
            // e.g. 09:00 - 17:00
            return hour >= start && hour < end
        } else {
            // e.g. 20:00 - 09:00 (crosses midnight)
            return hour >= start || hour < end
        }
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        errorMessage = nil

        let refreshStart = ContinuousClock.now
        let logger = RefreshLogger.shared
        let users = monitoredUsersService.users
        logger.log("Refresh started — \(users.count) user(s)")

        // Fetch Other PRs concurrently with user PRs
        async let otherFetchTask = fetchAllOtherPRs()

        // Fetch all users concurrently
        var userResults: [(UUID, MonitoredUser, Result<PRFetchResult, Error>)] = []
        await withTaskGroup(of: (UUID, MonitoredUser, Result<PRFetchResult, Error>).self) { group in
            for user in users {
                group.addTask { [githubService, enableInactiveBranchDetection, inactiveBranchThresholdDays, isDemoMode] in
                    let userStart = ContinuousClock.now
                    do {
                        let result: PRFetchResult
                        if isDemoMode {
                            result = PRFetchResult(pullRequests: DemoData.samplePullRequests, isPartial: false)
                        } else {
                            result = try await githubService.fetchPRsForUser(
                                username: user.username,
                                enableInactiveDetection: enableInactiveBranchDetection,
                                inactiveThresholdDays: inactiveBranchThresholdDays
                            )
                        }
                        let elapsed = ContinuousClock.now - userStart
                        await logger.log("\(user.username): \(result.pullRequests.count) PRs in \(elapsed)")
                        return (user.id, user, .success(result))
                    } catch {
                        let elapsed = ContinuousClock.now - userStart
                        await logger.log("\(user.username): FAILED in \(elapsed) — \(error.localizedDescription)")
                        return (user.id, user, .failure(error))
                    }
                }
            }
            for await result in group {
                userResults.append(result)
            }
        }

        let otherStart = ContinuousClock.now
        let fetchedOther = await otherFetchTask
        let otherElapsed = ContinuousClock.now - otherStart
        if !otherPRsService.all().isEmpty {
            logger.log("Other PRs: \(fetchedOther.count) in \(otherElapsed)")
        }

        // Process results for each user
        var anySuccess = false
        for (userId, user, result) in userResults {
            switch result {
            case .success(let fetchResult):
                anySuccess = true
                // Store raw PRs with watch status and custom names (before filtering)
                let rawPRs = applyCustomNames(fetchResult.pullRequests.map { pr in
                    var updated = pr
                    updated.isWatched = watchlistService.isWatched(pr)
                    return updated
                })
                var cache = PerUserPRCache()
                cache.rawPRs = rawPRs
                // Apply ignore filters
                let filtered = filterIgnoredRepos(rawPRs, user: user)
                let withIgnoredChecks = applyIgnoredChecks(filtered, user: user)
                let withInactiveFiltered = filterInactivePRs(withIgnoredChecks)
                cache.unsortedPRs = withInactiveFiltered
                cache.hasFailure = cache.unsortedPRs.contains {
                    $0.buildStatus == .failure || $0.buildStatus == .error ||
                    $0.buildStatus == .conflict || $0.reviewDecision == .changesRequested
                }
                cache.hasPending = cache.unsortedPRs.contains { $0.buildStatus == .pending }
                perUserCache[userId] = cache

            case .failure(let error):
                print("Error fetching PRs for \(user.username): \(error)")
                if let ghError = error as? GitHubError {
                    if ghError == .notInstalled || ghError == .notAuthenticated {
                        isGHAvailable = false
                        errorMessage = ghError.localizedDescription
                    }
                }
            }
        }

        if !anySuccess && !users.isEmpty {
            errorMessage = GitHubError.networkError.localizedDescription
        } else if errorMessage == nil {
            isGHAvailable = true
        }

        // Update Other PRs
        let otherIDs = Set(fetchedOther.map { $0.id })
        otherPullRequests = applyCustomNames(fetchedOther.map { pr in
            var updated = pr
            updated.isWatched = watchlistService.isWatched(pr)
            return updated
        })

        // Check completions across all cached PRs
        let allCachedPRs = Array(perUserCache.values.flatMap { $0.unsortedPRs }) + otherPullRequests
        let completed = watchlistService.checkForCompletions(currentPRs: allCachedPRs)
        for pr in completed {
            notificationService.notifyBuildComplete(pr: pr, status: pr.buildStatus)
        }

        // Prune stale custom names
        let activeIDs = Set(allCachedPRs.map { $0.id })
        customNamesService.pruneStale(keeping: activeIDs)

        // Switch to current user's cache (re-read selectedUserId in case user switched during fetch)
        let activeUserId = monitoredUsersService.selectedUserId
        if let activeUserId, let cache = perUserCache[activeUserId] {
            unsortedPullRequests = cache.unsortedPRs.filter { !otherIDs.contains($0.id) }
        } else if let activeUserId, perUserCache[activeUserId] == nil {
            // User was added but fetch hasn't returned data yet
            unsortedPullRequests = []
        }

        applySorting()

        // Reset repo filter if needed
        if selectedRepository != "All Repositories" &&
           !unsortedPullRequests.contains(where: { $0.repository.nameWithOwner == selectedRepository }) &&
           !otherPullRequests.contains(where: { $0.repository.nameWithOwner == selectedRepository }) {
            selectedRepository = "All Repositories"
        }

        lastRefreshTime = Date()
        isLoading = false
        persistCache()
        let totalElapsed = ContinuousClock.now - refreshStart
        logger.log("Refresh complete in \(totalElapsed)")
    }

    // MARK: - Filtering Helpers

    private func filterInactivePRs(_ prs: [PullRequest]) -> [PullRequest] {
        guard UserDefaults.standard.bool(forKey: "hideInactivePRs"),
              UserDefaults.standard.bool(forKey: "enableInactiveBranchDetection") else { return prs }
        let threshold = Double(inactiveBranchThresholdDays)
        return prs.filter { pr in
            // Check both the pre-computed status AND the actual date,
            // because cached PRs may have been fetched before inactive
            // detection was enabled and still have a non-inactive status.
            if pr.buildStatus == .inactive { return false }
            let daysSinceUpdate = Date().timeIntervalSince(pr.updatedAt) / Constants.secondsPerDay
            return daysSinceUpdate < threshold
        }
    }

    private func filterIgnoredRepos(_ prs: [PullRequest], user: MonitoredUser) -> [PullRequest] {
        let ignoredRepos = user.ignoredRepos + globalIgnoredRepos()
        guard !ignoredRepos.isEmpty else { return prs }
        let ignored = Set(ignoredRepos.map { $0.lowercased() })
        return prs.filter { !ignored.contains($0.repository.nameWithOwner.lowercased()) }
    }

    private func applyIgnoredChecks(_ prs: [PullRequest], user: MonitoredUser) -> [PullRequest] {
        let ignoredChecks = user.ignoredChecks + globalIgnoredChecks()
        guard !ignoredChecks.isEmpty else { return prs }
        return prs.map { pr in
            var updated = pr
            let repo = pr.repository.nameWithOwner
            let nonIgnoredChecks = pr.statusChecks.filter { check in
                !ignoredChecks.contains { rule in rule.matches(checkName: check.name, repo: repo) }
            }
            let ignoredFailingCount = pr.statusChecks.filter { check in
                (check.status == .failure || check.status == .error) &&
                ignoredChecks.contains { rule in rule.matches(checkName: check.name, repo: repo) }
            }.count
            updated.ignoredCheckCount = ignoredFailingCount
            updated.statusChecks = nonIgnoredChecks
            updated.buildStatus = computeStatus(from: nonIgnoredChecks, originalStatus: pr.buildStatus)
            return updated
        }
    }

    private func globalIgnoredRepos() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: GlobalRulesDefaults.ignoredReposKey),
              let repos = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return repos
    }

    private func globalIgnoredChecks() -> [IgnoredCheckRule] {
        guard let data = UserDefaults.standard.data(forKey: GlobalRulesDefaults.ignoredChecksKey),
              let rules = try? JSONDecoder().decode([IgnoredCheckRule].self, from: data) else {
            return []
        }
        return rules
    }

    private func computeStatus(from checks: [StatusCheck], originalStatus: BuildStatus) -> BuildStatus {
        // Preserve conflict status (comes from mergeable, not checks)
        if originalStatus == .conflict { return .conflict }
        // Preserve inactive status
        if originalStatus == .inactive { return .inactive }

        if checks.isEmpty { return .success }

        var hasFailure = false
        var hasError = false
        var hasPending = false

        for check in checks {
            switch check.status {
            case .failure: hasFailure = true
            case .error: hasError = true
            case .pending: hasPending = true
            case .success, .skipped: break
            }
        }

        if hasFailure { return .failure }
        if hasError { return .error }
        if hasPending { return .pending }
        return .success
    }

    private func updateGlobalWarningIcon() {
        let anyBadStatus = perUserCache.values.contains { $0.hasFailure }
        let anyInactive = perUserCache.values.contains { cache in
            cache.unsortedPRs.contains { $0.buildStatus == .inactive }
        }
        let meId = monitoredUsersService.users.first(where: { $0.isMe })?.id
        let anyReviewPRs: Bool
        if let meId, let meCache = perUserCache[meId] {
            anyReviewPRs = meCache.unsortedPRs.contains { $0.type == .reviewing }
        } else {
            anyReviewPRs = false
        }
        let otherBadStatus = otherPullRequests.contains { pr in
            pr.buildStatus == .failure || pr.buildStatus == .error ||
            pr.buildStatus == .conflict || pr.buildStatus == .inactive ||
            pr.reviewDecision == .changesRequested
        }
        showWarningIcon = anyBadStatus || anyInactive || anyReviewPRs || otherBadStatus
    }

    // MARK: - Other PRs

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
        updated.customName = customNamesService.name(for: pr.id)
        otherPullRequests.append(updated)
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
        customNamesService.removeName(for: pr.id)
        otherPullRequests.removeAll { $0.id == pr.id }
        applySorting()
        if selectedRepository != "All Repositories" &&
            !unsortedPullRequests.contains(where: { $0.repository.nameWithOwner == selectedRepository }) &&
            !otherPullRequests.contains(where: { $0.repository.nameWithOwner == selectedRepository }) {
            selectedRepository = "All Repositories"
        }
    }

    // MARK: - Sorting

    private func applySorting() {
        let authored = unsortedPullRequests.filter { $0.type == .authored }
        let review = unsortedPullRequests.filter { $0.type == .reviewing }

        let sortedAuthored = sortNonSuccessFirst ? sort(authored) : authored
        let sortedReview = sortNonSuccessFirst ? sort(review) : review

        let newPullRequests = sortedReview + sortedAuthored

        if newPullRequests != pullRequests {
            pullRequests = newPullRequests
        }

        updateGlobalWarningIcon()
    }

    private func sort(_ prs: [PullRequest]) -> [PullRequest] {
        prs.sorted { pr1, pr2 in
            let nonSuccessStatuses: [BuildStatus] = [.failure, .error, .conflict, .pending, .inactive]
            let pr1NonSuccess = nonSuccessStatuses.contains(pr1.buildStatus) || pr1.reviewDecision == .changesRequested
            let pr2NonSuccess = nonSuccessStatuses.contains(pr2.buildStatus) || pr2.reviewDecision == .changesRequested

            if pr1NonSuccess != pr2NonSuccess {
                return pr1NonSuccess
            }
            return false
        }
    }

    // MARK: - Custom Names

    private func applyCustomNames(_ prs: [PullRequest]) -> [PullRequest] {
        prs.map { pr in
            var updated = pr
            updated.customName = customNamesService.name(for: pr.id)
            return updated
        }
    }

    func renamePR(_ pr: PullRequest, to name: String?) {
        if let name, !name.isEmpty {
            customNamesService.setName(name, for: pr.id)
        } else {
            customNamesService.removeName(for: pr.id)
        }
        unsortedPullRequests = applyCustomNames(unsortedPullRequests)
        pullRequests = applyCustomNames(pullRequests)
        otherPullRequests = applyCustomNames(otherPullRequests)
    }

    // MARK: - Watch

    func toggleWatch(for pr: PullRequest) {
        if watchlistService.isWatched(pr) {
            watchlistService.unwatch(pr)
        } else {
            watchlistService.watch(pr)
        }

        if let index = unsortedPullRequests.firstIndex(where: { $0.id == pr.id }) {
            unsortedPullRequests[index].isWatched.toggle()
        }
        if let index = pullRequests.firstIndex(where: { $0.id == pr.id }) {
            pullRequests[index].isWatched.toggle()
        }
        if let index = otherPullRequests.firstIndex(where: { $0.id == pr.id }) {
            otherPullRequests[index].isWatched.toggle()
        }
    }

    func clearAllWatched() {
        watchlistService.clearAll()
        for index in unsortedPullRequests.indices {
            unsortedPullRequests[index].isWatched = false
        }
        for index in pullRequests.indices {
            pullRequests[index].isWatched = false
        }
        for index in otherPullRequests.indices {
            otherPullRequests[index].isWatched = false
        }
    }

    // MARK: - GH Availability

    private func checkGHAvailability() async {
        do {
            try await githubService.checkGHAvailable()
            isGHAvailable = true
            errorMessage = nil
        } catch let error as GitHubError {
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

    @objc dynamic var disableAutoRefresh: Bool {
        return bool(forKey: "disableAutoRefresh")
    }

    @objc dynamic var hideInactivePRs: Bool {
        return bool(forKey: "hideInactivePRs")
    }
}
