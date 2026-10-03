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
    /// How long a stack resolution is reused before the lookup repeats. Instance
    /// state so tests can inject a tiny interval.
    private let stackResolutionTTL: TimeInterval

    private var refreshTimer: Timer?
    private var defaultsObserver: AnyCancellable?
    private var unsortedPullRequests: [PullRequest] = []
    private var copiedPRLinkTask: Task<Void, Never>?
    /// Stack ids already notified ready, seeded from preferences at launch so a
    /// relaunch does not notify again for a stack that is still ready.
    private var readyStackIDs: Set<String> = []
    /// Completed stacks for this session, keyed by stack id, so a poll that
    /// still shows the same visible parts reuses the earlier lookup.
    private var stackResolutionCache: [String: StackResolutionCacheEntry] = [:]
    /// Stack parts the user removed, by PR id. Completion would otherwise
    /// re-add them as companions for as long as a sibling anchor stays in a list.
    private var removedStackPartIDs: Set<String> = []
    /// Stack parts currently in the lists only because completion added them,
    /// by PR id. Rebuilt on every refresh from the parts actually appended, so
    /// `isStackCompanion(_:)` can mark rows the user did not ask to track.
    private var stackCompanionIDs: Set<String> = []

    /// Stack blocks the user collapsed, by stack id. Session state: a freshly
    /// launched app starts with every block expanded.
    @Published private(set) var collapsedStackIDs: Set<String> = []

    var copyClearTask: Task<Void, Never>? { copiedPRLinkTask }

    var selectedRepository: String {
        get {
            let selected = defaults.string(forKey: PreferenceKeys.selectedRepository) ?? "All Repositories"
            return availableRepositories.first { $0.lowercased() == selected.lowercased() } ?? selected
        }
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
        var namesByRepository: [String: String] = [:]
        for pr in unsortedPullRequests + otherPullRequests {
            let name = pr.repository.nameWithOwner
            let normalizedName = name.lowercased()
            if namesByRepository[normalizedName] == nil {
                namesByRepository[normalizedName] = name
            }
        }
        return namesByRepository.values.sorted()
    }

    var reposWithIssues: Set<String> {
        let allPRs = unsortedPullRequests + otherPullRequests
        let visiblePRs = hideInactivePRs ? allPRs.filter { !isInactiveByAge($0) } : allPRs
        let displayNames = Dictionary(uniqueKeysWithValues: availableRepositories.map { ($0.lowercased(), $0) })
        return Set(visiblePRs.compactMap { pr -> String? in
            let badBuild = pr.buildStatus == .failure || pr.buildStatus == .error
                || pr.buildStatus == .conflict || pr.buildStatus == .notStarted
                || pr.buildStatus == .inactive
            guard badBuild || pr.reviewDecision == .changesRequested else { return nil }
            return displayNames[pr.repository.nameWithOwner.lowercased()]
        })
    }

    /// Rows for a section: unstacked PRs as-is, each stack as one block (header plus
    /// its parts in merge order, part 1 first so the base sits at the top).
    func sectionRows(for type: PRType) -> [PRListRow] {
        PRStackOrdering.rows(from: sectionPRs(for: type), collapsedStackIDs: collapsedStackIDs)
    }

    var authoredPRs: [PullRequest] {
        PRStackOrdering.rows(from: sectionPRs(for: .authored)).compactMap(\.pr)
    }

    var reviewPRs: [PullRequest] {
        PRStackOrdering.rows(from: sectionPRs(for: .reviewing)).compactMap(\.pr)
    }

    var filteredOtherPRs: [PullRequest] {
        PRStackOrdering.rows(from: sectionPRs(for: .other)).compactMap(\.pr)
    }

    private func sectionPRs(for type: PRType) -> [PullRequest] {
        // A stack may span Authored, Reviewing, and pinned Other. Render all
        // visible members together under the lowest-position member's category.
        let visible = (pullRequests + otherPullRequests).filter { pr in
            guard matchesSelectedRepository(pr) else { return false }
            switch pr.type {
            case .reviewing: return showReviewPRs
            case .authored: return !hideInactivePRs || !isInactiveByAge(pr)
            case .other: return !hideInactivePRs || !isInactiveByAge(pr)
            }
        }
        var lowestByStack: [String: PullRequest] = [:]
        for pr in visible {
            guard let stack = pr.stack else { continue }
            if stack.position < (lowestByStack[stack.id]?.stack?.position ?? Int.max) {
                lowestByStack[stack.id] = pr
            }
        }
        return visible.filter { pr in
            guard let stack = pr.stack else { return pr.type == type }
            return lowestByStack[stack.id]?.type == type
        }
    }

    private func matchesSelectedRepository(_ pr: PullRequest) -> Bool {
        selectedRepository == "All Repositories"
            || pr.repository.nameWithOwner.lowercased() == selectedRepository.lowercased()
    }

    private func isInactiveByAge(_ pr: PullRequest) -> Bool {
        guard enableInactiveBranchDetection else { return pr.buildStatus == .inactive }
        let daysSinceUpdate = Date().timeIntervalSince(pr.updatedAt) / Constants.secondsPerDay
        return daysSinceUpdate >= Double(inactiveBranchThresholdDays)
    }

    init(
        isDemoMode: Bool = false,
        stackResolutionTTL: TimeInterval = Constants.stackResolutionRevalidationInterval
    ) {
        self.isDemoMode = isDemoMode
        self.stackResolutionTTL = stackResolutionTTL
        readyStackIDs = loadNotifiedReadyStackIDs()
        removedStackPartIDs = loadRemovedStackPartIDs()
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
        let cached = cacheService.loadMainPRs().filter { !removedStackPartIDs.contains($0.id.lowercased()) }
        if !cached.isEmpty {
            unsortedPullRequests = cached.map {
                var pr = $0; pr.isWatched = watchlistService.isWatched(pr); return pr
            }
            applySorting()
        }
        otherPullRequests = cacheService.loadOtherPRs().filter { !removedStackPartIDs.contains($0.id.lowercased()) }.map {
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
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
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

            let otherIDs = Set(fetchedOther.map { $0.id.lowercased() })
            let dedupedPRs = fetchedPRs.filter { !otherIDs.contains($0.id.lowercased()) }

            let completedStacks = await completeStacks(mainPRs: dedupedPRs, otherPRs: fetchedOther)
            let mainPRs = completedStacks.main
            let otherPRs = completedStacks.other

            let completed = watchlistService.checkForCompletions(currentPRs: mainPRs + otherPRs)

            for pr in completed {
                notificationService.notifyBuildComplete(pr: pr, status: pr.buildStatus)
            }

            unsortedPullRequests = applyCustomNames(mainPRs.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            })

            otherPullRequests = applyCustomNames(otherPRs.map { pr in
                var updated = pr
                updated.isWatched = watchlistService.isWatched(pr)
                return updated
            })

            let activeIDs = Set((mainPRs + otherPRs).map { $0.id })
            customNamesService.pruneStale(keeping: activeIDs)

            applySorting()
            // A partial fetch omits whole stacks when one host's search fails, and
            // readinessTransitions rebuilds the ready set from only the PRs present,
            // so a stack missing here would be wrongly read as "no longer ready" and
            // re-notify on the next full refresh. Defer the evaluation to the next
            // full refresh instead.
            if !fetchResult.isPartial {
                notifyReadyStacks(allPRs: mainPRs + otherPRs, excluding: completedStacks.unverifiedStackIDs)
            }

            if !fetchResult.isPartial &&
                selectedRepository != "All Repositories" &&
                !unsortedPullRequests.contains(where: matchesSelectedRepository) &&
                !otherPullRequests.contains(where: matchesSelectedRepository) {
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

    /// One stack's completion lookup, kept for the session so a poll that still
    /// shows the same visible parts reuses it instead of repeating the lookup.
    private struct StackResolutionCacheEntry {
        /// The PR numbers visible in the fetch when the stack was resolved. A
        /// poll showing different numbers invalidates the entry: the stack moved.
        let visibleNumbers: Set<Int>
        /// The open parts the lookup returned that were not visible then.
        let companionParts: [PullRequest]
        /// Positions whose pull request had already merged.
        let mergedPositions: [Int]
        /// When the stack was resolved, for the revalidation interval.
        let resolvedAt: Date
    }

    /// Fetches the parts of any incomplete stack so a stack renders as a whole even
    /// when only one of its PRs matched the user's searches. Companions join the
    /// anchor's list and are marked (`isStackCompanion`) so their rows can show
    /// they are someone else's PR rather than something from the user's own lists.
    ///
    /// Resolutions are cached per stack for the session: while the fetch keeps
    /// showing the same visible parts and the revalidation interval has not
    /// elapsed, the earlier lookup is reused instead of refetched. A failed
    /// lookup can reuse previously displayed parts without caching the failure.
    /// Parts the user removed are never re-added as companions.
    private func completeStacks(
        mainPRs: [PullRequest],
        otherPRs: [PullRequest]
    ) async -> (main: [PullRequest], other: [PullRequest], unverifiedStackIDs: Set<String>) {
        guard !isDemoMode else { return (mainPRs, otherPRs, []) }

        // Collected locally and published once at the end, so the marks on the
        // still-displayed lists never flicker off while this function is
        // suspended on network awaits. Rebuilt fresh every call from the parts
        // appended below, so a part that stops being a companion (it matched a
        // search, merged, or closed) loses its marking on the same refresh.
        var companionIDs: Set<String> = []

        let knownIDs = Set((mainPRs + otherPRs).map { $0.id.lowercased() })
        let fetchedStackIDs = Set((mainPRs + otherPRs).compactMap { $0.stack?.id })
        // On launch the PR cache has the displayed parts, but not this session's
        // companion marks. Identify cached parts absent from the current search
        // before awaiting completion, so they can still be pinned while it runs.
        stackCompanionIDs.formUnion((unsortedPullRequests + otherPullRequests).filter { pr in
            guard let stackID = pr.stack?.id else { return false }
            return fetchedStackIDs.contains(stackID)
                && !knownIDs.contains(pr.id.lowercased())
                && !removedStackPartIDs.contains(pr.id.lowercased())
                && !isPinnedPR(pr)
        }.map(\.id))
        var knownNumbers: [String: Set<Int>] = [:]
        for pr in mainPRs + otherPRs {
            guard let stack = pr.stack else { continue }
            knownNumbers[stack.id, default: []].insert(pr.number)
        }

        var main = mainPRs
        var other = otherPRs
        var visitedStacks: Set<String> = []
        var unverifiedStackIDs: Set<String> = []

        for anchor in mainPRs + otherPRs {
            guard let stack = anchor.stack,
                  visitedStacks.insert(stack.id).inserted,
                  let numbers = knownNumbers[stack.id],
                  numbers.count < stack.size else { continue }

            let completion: StackCompletion
            let cached = stackResolutionCache[stack.id]
            if let cached, cached.visibleNumbers == numbers,
               Date().timeIntervalSince(cached.resolvedAt) < stackResolutionTTL {
                // The fetch shows the same parts as when this stack was resolved,
                // so reuse the earlier lookup instead of another round trip.
                // Its companion status is not fresh enough for a notification.
                unverifiedStackIDs.insert(stack.id)
                completion = StackCompletion(
                    missingParts: cached.companionParts,
                    mergedPositions: cached.mergedPositions
                )
            } else {
                if let resolved = await missingParts(for: anchor, stack: stack, knownNumbers: numbers) {
                    completion = resolved
                    stackResolutionCache[stack.id] = StackResolutionCacheEntry(
                        visibleNumbers: numbers,
                        companionParts: resolved.missingParts,
                        mergedPositions: resolved.mergedPositions,
                        resolvedAt: Date()
                    )
                } else if let cached {
                    // Revalidation failed: keep this stack's earlier companions
                    // for this refresh, but leave the cache timestamp untouched
                    // so the next poll retries the lookup.
                    unverifiedStackIDs.insert(stack.id)
                    completion = StackCompletion(
                        missingParts: cached.companionParts,
                        mergedPositions: cached.mergedPositions
                    )
                } else if let displayed = displayedCompletion(for: stack, knownIDs: knownIDs) {
                    // A new VM has no resolution cache, but its restored PR lists
                    // may still hold companions from the previous session.
                    unverifiedStackIDs.insert(stack.id)
                    completion = displayed
                } else {
                    unverifiedStackIDs.insert(stack.id)
                    continue
                }
            }

            // Exclusions are stored lowercased (see removeOtherPR), so compare the
            // companion's id lowercased as well.
            let parts = completion.missingParts.filter {
                !knownIDs.contains($0.id.lowercased())
                    && !removedStackPartIDs.contains($0.id.lowercased())
                    && !isPinnedPR($0)
            }
            companionIDs.formUnion(parts.map(\.id))

            if mainPRs.contains(where: { $0.stack?.id == stack.id }) {
                main.append(contentsOf: parts)
            } else {
                other.append(contentsOf: parts)
            }

            // Record the merged positions on every part of this stack, so readiness
            // and the header can account for rows GitHub no longer returns.
            for index in main.indices where main[index].stack?.id == stack.id {
                main[index].stack?.mergedPositions = completion.mergedPositions
            }
            for index in other.indices where other[index].stack?.id == stack.id {
                other[index].stack?.mergedPositions = completion.mergedPositions
            }
        }

        // Adding a pin can finish while a stack lookup is suspended. The Other
        // fetch then predates the new pin; keep that live pin and remove any
        // duplicate companion from the main-list result before publishing.
        let currentPinned = otherPullRequests.filter { $0.stack != nil && isPinnedPR($0) }
        let pinnedIDs = Set(currentPinned.map { $0.id.lowercased() })
        main.removeAll { pinnedIDs.contains($0.id.lowercased()) }
        other.removeAll { removedStackPartIDs.contains($0.id.lowercased()) && !isPinnedPR($0) }
        let otherIDs = Set(other.map { $0.id.lowercased() })
        let retainedPins = currentPinned.filter { !otherIDs.contains($0.id.lowercased()) }
        // These pins came from the displayed list rather than this refresh's
        // Other fetch, so their status is not verified either.
        unverifiedStackIDs.formUnion(retainedPins.compactMap { $0.stack?.id })
        other.append(contentsOf: retainedPins)

        // Publish the rebuilt companion marks in one step, after every network
        // await in this function has resolved.
        stackCompanionIDs = companionIDs
        return (main, other, unverifiedStackIDs)
    }

    private func displayedCompletion(for stack: PRStackInfo, knownIDs: Set<String>) -> StackCompletion? {
        let displayed = (unsortedPullRequests + otherPullRequests).filter { $0.stack?.id == stack.id }
        guard !displayed.isEmpty else { return nil }
        return StackCompletion(
            missingParts: displayed.filter { !knownIDs.contains($0.id.lowercased()) && !isPinnedPR($0) },
            mergedPositions: displayed.compactMap { $0.stack?.mergedPositions }.first ?? []
        )
    }

    /// Resolves the missing parts of a stack, or nil when the lookup failed. A
    /// successful empty result is still a result: it means the stack has no open
    /// parts beyond the visible ones.
    private func missingParts(
        for anchor: PullRequest,
        stack: PRStackInfo,
        knownNumbers: Set<Int>
    ) async -> StackCompletion? {
        let components = anchor.repository.nameWithOwner.split(separator: "/")
        guard components.count == 2 else { return .empty }

        do {
            return try await githubService.fetchMissingStackParts(
                stackID: stack.id,
                host: anchor.host,
                owner: String(components[0]),
                repo: String(components[1]),
                knownNumbers: knownNumbers,
                type: anchor.type,
                enableInactiveDetection: enableInactiveBranchDetection,
                inactiveThresholdDays: inactiveBranchThresholdDays
            )
        } catch {
            // Completing a stack is best-effort; the caller can reuse a prior
            // resolution for this refresh, and retries on the next poll.
            print("Transient error completing stack #\(stack.number): \(error)")
            return nil
        }
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
        func matchesPR(_ pr: PullRequest) -> Bool {
            pr.number == id.number && pr.repository.nameWithOwner.lowercased() == normalizedRepo
        }
        guard !unsortedPullRequests.contains(where: { matchesPR($0) && !isStackCompanion($0) }) else {
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
        // Re-adding a part revokes the persisted exclusion from an earlier removal.
        if removedStackPartIDs.remove(pr.id.lowercased()) != nil {
            saveRemovedStackPartIDs()
        }
        var updated = pr
        updated.isWatched = watchlistService.isWatched(pr)
        updated.customName = customNamesService.name(for: pr.id)
        otherPullRequests.removeAll(where: matchesPR)
        otherPullRequests.append(updated)
        unsortedPullRequests.removeAll(where: matchesPR)
        pullRequests.removeAll(where: matchesPR)
        applySorting()
    }

    /// True when the user pinned this PR, as opposed to a stack companion that is
    /// only in the list because another part of its stack is pinned.
    func isPinnedPR(_ pr: PullRequest) -> Bool {
        guard let id = otherPRIdentifier(for: pr) else { return false }
        return otherPRsService.contains(id)
    }

    /// True when this PR is a stack companion: a part the completion lookup
    /// added because a sibling anchored a stack in the user's lists, not
    /// something the user tracks themselves. Pinned PRs win: a part the user
    /// added by URL is theirs, not a companion.
    func isStackCompanion(_ pr: PullRequest) -> Bool {
        stackCompanionIDs.contains(pr.id) && !isPinnedPR(pr)
    }

    private func otherPRIdentifier(for pr: PullRequest) -> OtherPRIdentifier? {
        let parts = pr.repository.nameWithOwner.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return OtherPRIdentifier(
            host: pr.host,
            owner: String(parts[0]),
            repo: String(parts[1]),
            number: pr.number
        )
    }

    func removeOtherPR(_ pr: PullRequest) {
        guard let id = otherPRIdentifier(for: pr) else { return }
        otherPRsService.remove(id)
        customNamesService.removeName(for: pr.id)
        // Only stacked parts can reappear once their pin is gone: completion
        // re-adds them as companions while a sibling anchor remains in a list.
        // Non-stacked PRs stay removed on their own, so they need no exclusion.
        // Exclusions are lowercased because a pinned part's id casing comes from
        // the URL the user typed, while completion rebuilds companions with the
        // anchor's API-canonical casing.
        if pr.stack != nil, removedStackPartIDs.insert(pr.id.lowercased()).inserted {
            saveRemovedStackPartIDs()
        }
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
            if pr1.isMergeBlocked != pr2.isMergeBlocked {
                return pr1.isMergeBlocked
            }

            return false
        }
    }

    /// Number of stack parts the app knows about for the given PR; 1 when the PR is
    /// not stacked, so a stack is watched as a unit.
    func stackMemberCount(for pr: PullRequest) -> Int {
        stackMembers(of: pr).count
    }

    func toggleStackCollapse(_ stackID: String) {
        if collapsedStackIDs.contains(stackID) {
            collapsedStackIDs.remove(stackID)
        } else {
            collapsedStackIDs.insert(stackID)
        }
    }

    func isStackCollapsed(_ stackID: String) -> Bool {
        collapsedStackIDs.contains(stackID)
    }

    /// Number of stack parts the app knows about for the given stack id.
    func stackMemberCount(forStackID stackID: String) -> Int {
        stackMembers(stackID: stackID).count
    }

    /// The stack's known parts in merge order (part 1 first), for opening them all.
    func stackParts(inStack stackID: String) -> [PullRequest] {
        stackMembers(stackID: stackID).sorted {
            ($0.stack?.position ?? 0) < ($1.stack?.position ?? 0)
        }
    }

    func isStackWatched(_ stackID: String) -> Bool {
        stackMembers(stackID: stackID).contains { watchlistService.isWatched($0) }
    }

    /// Watches or unwatches every known part of a stack.
    func toggleWatchForStack(_ stackID: String) {
        let members = stackMembers(stackID: stackID)
        let shouldWatch = !members.contains { watchlistService.isWatched($0) }
        updateWatch(members, to: shouldWatch)
    }

    func toggleWatch(for pr: PullRequest) {
        let members = stackMembers(of: pr)
        let shouldWatch = !watchlistService.isWatched(pr)
        updateWatch(members, to: shouldWatch)
    }

    private func updateWatch(_ members: [PullRequest], to shouldWatch: Bool) {
        for member in members {
            if shouldWatch {
                watchlistService.watch(member)
            } else {
                watchlistService.unwatch(member)
            }
            setWatched(member.id, shouldWatch)
        }
    }

    private func stackMembers(of pr: PullRequest) -> [PullRequest] {
        guard let stackID = pr.stack?.id else { return [pr] }
        let members = stackMembers(stackID: stackID)
        return members.isEmpty ? [pr] : members
    }

    private func stackMembers(stackID: String) -> [PullRequest] {
        (unsortedPullRequests + otherPullRequests).filter { $0.stack?.id == stackID }
    }

    private func setWatched(_ prID: String, _ isWatched: Bool) {
        if let index = unsortedPullRequests.firstIndex(where: { $0.id == prID }) {
            unsortedPullRequests[index].isWatched = isWatched
        }
        if let index = pullRequests.firstIndex(where: { $0.id == prID }) {
            pullRequests[index].isWatched = isWatched
        }
        if let index = otherPullRequests.firstIndex(where: { $0.id == prID }) {
            otherPullRequests[index].isWatched = isWatched
        }
    }

    /// Notifies once per watched stack when it is ready to merge. A stack that
    /// becomes ready before anyone watches it stays pending, so watching it later
    /// still produces the notification on the next verified refresh. The ids of stacks
    /// already notified ready persist across launches; a stack that regresses is
    /// dropped from them so its recovery notifies again.
    private func notifyReadyStacks(allPRs: [PullRequest], excluding unverifiedStackIDs: Set<String>) {
        let previouslyReady = readyStackIDs
        let verifiedPRs = allPRs.filter { pr in
            guard let stackID = pr.stack?.id else { return true }
            return !unverifiedStackIDs.contains(stackID)
        }
        let transition = PRStackOrdering.readinessTransitions(previouslyReady: previouslyReady, prs: verifiedPRs)
        // An unverified stack is neither newly ready nor known to have regressed.
        // Keep its previous membership until a successful lookup can decide.
        readyStackIDs = transition.readyStackIDs.union(previouslyReady.intersection(unverifiedStackIDs))

        for readyStack in transition.newlyReady {
            let hasWatchedMember = allPRs.contains {
                $0.stack?.id == readyStack.id && watchlistService.isWatched($0)
            }
            guard hasWatchedMember else {
                readyStackIDs.remove(readyStack.id)
                continue
            }
            notificationService.notifyStackReady(stack: readyStack)
        }

        if readyStackIDs != previouslyReady {
            saveNotifiedReadyStackIDs(readyStackIDs)
        }
    }

    /// The stack ids already notified ready, persisted so a relaunch does not
    /// re-notify a stack that is still ready and still watched.
    private func loadNotifiedReadyStackIDs() -> Set<String> {
        guard let data = defaults.data(forKey: PreferenceKeys.notifiedReadyStacks),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    private func saveNotifiedReadyStackIDs(_ ids: Set<String>) {
        if let data = try? JSONEncoder().encode(ids.sorted()) {
            defaults.set(data, forKey: PreferenceKeys.notifiedReadyStacks)
        }
    }

    private func loadRemovedStackPartIDs() -> Set<String> {
        guard let data = defaults.data(forKey: PreferenceKeys.removedStackPartIDs),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(ids.map { $0.lowercased() })
    }

    private func saveRemovedStackPartIDs() {
        if let data = try? JSONEncoder().encode(removedStackPartIDs.sorted()) {
            defaults.set(data, forKey: PreferenceKeys.removedStackPartIDs)
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
        copiedPRLinkTask?.cancel()
        copiedPRLinkTask = Task { [weak self, clock] in
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
