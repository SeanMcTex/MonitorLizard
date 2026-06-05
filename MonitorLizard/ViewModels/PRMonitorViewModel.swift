import Clocks
import Combine
import Dependencies
import Foundation
import SwiftUI

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
    @Published private(set) var copiedPRID: String? = nil

    @Dependency(UserDefaultsStore.self) private var defaults
    @Dependency(WatchlistServiceKey.self) private var watchlistService
    @Dependency(NotificationServiceKey.self) private var notificationService
    @Dependency(OtherPRsServiceKey.self) private var otherPRsService
    @Dependency(CustomNamesServiceKey.self) private var customNamesService
    @Dependency(PRCacheServiceKey.self) private var cacheService
    @Dependency(GitHubServiceKey.self) private var githubService
    @Dependency(PasteboardClientKey.self) private var pasteboard
    @Dependency(\.continuousClock) private var clock

    private let isDemoMode: Bool

    private var refreshTimer: Timer?
    private var defaultsObserver: AnyCancellable?
    private var unsortedPullRequests: [PullRequest] = []

    var selectedRepository: String {
        get { defaults.string(forKey: PreferenceKeys.selectedRepository) ?? "All Repositories" }
        set {
            defaults.set(newValue, forKey: PreferenceKeys.selectedRepository)
            objectWillChange.send()
        }
    }

    var selectedRepositoryBinding: Binding<String> {
        Binding(
            get: { self.selectedRepository },
            set: { self.selectedRepository = $0 }
        )
    }

    var refreshInterval: Int {
        defaults.object(forKey: PreferenceKeys.refreshInterval) as? Int ?? Constants.defaultRefreshInterval
    }

    private var sortNonSuccessFirst: Bool {
        defaults.bool(forKey: PreferenceKeys.sortNonSuccessFirst)
    }

    private var showReviewPRs: Bool {
        defaults.object(forKey: PreferenceKeys.showReviewPRs) as? Bool ?? true
    }

    private var enableInactiveBranchDetection: Bool {
        defaults.bool(forKey: PreferenceKeys.enableInactiveBranchDetection)
    }

    private var hideInactivePRs: Bool {
        defaults.bool(forKey: PreferenceKeys.hideInactivePRs)
    }

    private var inactiveBranchThresholdDays: Int {
        defaults.object(forKey: PreferenceKeys.inactiveBranchThresholdDays) as? Int ?? Constants.defaultInactiveBranchThreshold
    }

    var availableRepositories: [String] {
        let mainRepos = Set(unsortedPullRequests.map { $0.repository.nameWithOwner })
        let otherRepos = Set(otherPullRequests.map { $0.repository.nameWithOwner })
        return mainRepos.union(otherRepos).sorted()
    }

    var reposWithIssues: Set<String> {
        let allPRs = unsortedPullRequests + otherPullRequests
        let visiblePRs = hideInactivePRs ? allPRs.filter { !isInactiveByAge($0) } : allPRs
        return Set(visiblePRs.compactMap { pr -> String? in
            let badBuild = pr.buildStatus == .failure || pr.buildStatus == .error
                || pr.buildStatus == .conflict || pr.buildStatus == .notStarted
                || pr.buildStatus == .inactive
            guard badBuild || pr.reviewDecision == .changesRequested else { return nil }
            return pr.repository.nameWithOwner
        })
    }

    var authoredPRs: [PullRequest] {
        let prs = pullRequests.filter { $0.type == .authored }
            .filter { selectedRepository == "All Repositories" || $0.repository.nameWithOwner == selectedRepository }
        return hideInactivePRs ? prs.filter { !isInactiveByAge($0) } : prs
    }

    var reviewPRs: [PullRequest] {
        guard showReviewPRs else { return [] }
        let prs = pullRequests.filter { $0.type == .reviewing }
            .filter { selectedRepository == "All Repositories" || $0.repository.nameWithOwner == selectedRepository }
        return prs
    }

    var filteredOtherPRs: [PullRequest] {
        let prs = otherPullRequests
            .filter { selectedRepository == "All Repositories" || $0.repository.nameWithOwner == selectedRepository }
        return hideInactivePRs ? prs.filter { !isInactiveByAge($0) } : prs
    }

    private func isInactiveByAge(_ pr: PullRequest) -> Bool {
        guard enableInactiveBranchDetection else { return pr.buildStatus == .inactive }
        let daysSinceUpdate = Date().timeIntervalSince(pr.updatedAt) / Constants.secondsPerDay
        return daysSinceUpdate >= Double(inactiveBranchThresholdDays)
    }

    init(isDemoMode: Bool = false) {
        self.isDemoMode = isDemoMode
        restoreFromCache()
        setupNotifications()
        startPolling()
        observeDefaultsChanges()
    }

    deinit {
        MainActor.assumeIsolated {
            refreshTimer?.invalidate()
            defaultsObserver?.cancel()
        }
    }

    private func restoreFromCache() {
        let cached = cacheService.loadMainPRs()
        if !cached.isEmpty {
            unsortedPullRequests = cached.map {
                var pr = $0; pr.isWatched = watchlistService.isWatched(pr); return pr
            }
            applySorting()
        }
        otherPullRequests = cacheService.loadOtherPRs().map {
            var pr = $0; pr.isWatched = watchlistService.isWatched(pr); return pr
        }
    }

    private func observeDefaultsChanges() {
        let underlying = defaults.underlyingDefaults
        defaultsObserver = underlying
            .publisher(for: \.sortNonSuccessFirstDisplay)
            .merge(with: underlying.publisher(for: \.showReviewPRsDisplay))
            .merge(with: underlying.publisher(for: \.hideInactivePRsDisplay))
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.applySorting()
            }
    }

    func startPolling() {
        refreshTimer?.invalidate()

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(refreshInterval),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }

        Task {
            await refresh()
        }
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func updateRefreshInterval(_ interval: Int) {
        defaults.set(interval, forKey: PreferenceKeys.refreshInterval)
        startPolling()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil

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

            let otherIDs = Set(fetchedOther.map { $0.id })
            let dedupedPRs = fetchedPRs.filter { !otherIDs.contains($0.id) }

            let completed = watchlistService.checkForCompletions(currentPRs: dedupedPRs + fetchedOther)

            for pr in completed {
                notificationService.notifyBuildComplete(pr: pr, status: pr.buildStatus)
            }

            unsortedPullRequests = applyCustomNames(dedupedPRs.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            })

            otherPullRequests = applyCustomNames(fetchedOther.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            })

            let activeIDs = Set((dedupedPRs + fetchedOther).map { $0.id })
            customNamesService.pruneStale(keeping: activeIDs)

            applySorting()

            if !fetchResult.isPartial &&
                selectedRepository != "All Repositories" &&
                !unsortedPullRequests.contains(where: { $0.repository.nameWithOwner == selectedRepository }) &&
                !otherPullRequests.contains(where: { $0.repository.nameWithOwner == selectedRepository }) {
                selectedRepository = "All Repositories"
            }

            cacheService.save(mainPRs: unsortedPullRequests, otherPRs: otherPullRequests)

            lastRefreshTime = Date()
            isGHAvailable = true

        } catch let error as GitHubError {
            print("GitHubError: \(error)")
            errorMessage = error.localizedDescription
            if error == .notInstalled || error == .notAuthenticated {
                isGHAvailable = false
            }
            let fetchedOther = await otherFetchTask
            otherPullRequests = applyCustomNames(fetchedOther.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            })
        } catch let error as ShellError {
            print("ShellError: \(error)")
            errorMessage = error.localizedDescription
            let fetchedOther = await otherFetchTask
            otherPullRequests = applyCustomNames(fetchedOther.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            })
        } catch let error as DecodingError {
            print("DecodingError: \(error)")
            errorMessage = "Failed to parse GitHub data. Please try again."
            let fetchedOther = await otherFetchTask
            otherPullRequests = applyCustomNames(fetchedOther.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            })
        } catch {
            print("Unknown error: \(error)")
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
            let fetchedOther = await otherFetchTask
            otherPullRequests = applyCustomNames(fetchedOther.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            })
        }

        isLoading = false
    }

    private func fetchAllOtherPRs() async -> [PullRequest] {
        let ids = otherPRsService.all()
        var results: [PullRequest] = []
        var staleIDs: [OtherPRIdentifier] = []
        for id in ids {
            do {
                if let pr = try await githubService.fetchOtherPR(
                    id,
                    enableInactiveDetection: enableInactiveBranchDetection,
                    inactiveThresholdDays: inactiveBranchThresholdDays
                ) {
                    results.append(pr)
                } else {
                    staleIDs.append(id)
                }
            } catch {
                print("Transient error fetching Other PR \(id.owner)/\(id.repo)#\(id.number): \(error)")
            }
        }
        for id in staleIDs {
            otherPRsService.remove(id)
            customNamesService.removeName(for: "\(id.owner)/\(id.repo)#\(id.number)")
        }
        return results
    }

    private func applySorting() {
        let authored = unsortedPullRequests.filter { $0.type == .authored }
        let review = unsortedPullRequests.filter { $0.type == .reviewing }

        let sortedAuthored = sortNonSuccessFirst ? sort(authored) : authored
        let sortedReview = sortNonSuccessFirst ? sort(review) : review

        let newPullRequests = sortedReview + sortedAuthored

        if newPullRequests != pullRequests {
            pullRequests = newPullRequests
        }

        var allDisplayed = newPullRequests + otherPullRequests
        if hideInactivePRs {
            allDisplayed = allDisplayed.filter { !isInactiveByAge($0) }
        }
        let hasBadStatus = allDisplayed.contains { pr in
            let badBuild = pr.buildStatus == .failure || pr.buildStatus == .error
                || pr.buildStatus == .conflict || pr.buildStatus == .notStarted
                || pr.buildStatus == .inactive
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
        guard let pr = try await githubService.fetchOtherPR(
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

    private func sort(_ prs: [PullRequest]) -> [PullRequest] {
        prs.sorted { pr1, pr2 in
            let nonSuccessStatuses: [BuildStatus] = [.failure, .error, .conflict, .notStarted, .pending, .inactive]
            let pr1NonSuccess = nonSuccessStatuses.contains(pr1.buildStatus) || pr1.reviewDecision == .changesRequested
            let pr2NonSuccess = nonSuccessStatuses.contains(pr2.buildStatus) || pr2.reviewDecision == .changesRequested

            if pr1NonSuccess != pr2NonSuccess {
                return pr1NonSuccess
            }

            return false
        }
    }

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

    func copyPRLink(for pr: PullRequest) {
        pasteboard.copy(pr.url)
        copiedPRID = pr.id
        Task { [weak self, clock] in
            try? await clock.sleep(for: .seconds(2))
            self?.copiedPRID = nil
        }
    }

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

extension UserDefaults {
    @objc dynamic var sortNonSuccessFirstDisplay: Bool { bool(forKey: "sortNonSuccessFirst") }
    @objc dynamic var showReviewPRsDisplay: Bool { bool(forKey: "showReviewPRs") }
    @objc dynamic var hideInactivePRsDisplay: Bool { bool(forKey: "hideInactivePRs") }
}
