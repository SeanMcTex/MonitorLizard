import Dependencies
import Foundation
import Testing
@testable import MonitorLizard

struct ResolveReviewDecisionTests {

    typealias Review = GHPRDetailResponse.Review
    typealias ReviewAuthor = GHPRDetailResponse.Review.ReviewAuthor
    typealias ReviewRequest = GHPRDetailResponse.ReviewRequest

    enum Scenario: CaseIterable, Sendable {
        case approvedPassesThrough
        case reviewRequiredPassesThrough
        case nilRawValueReturnsNil
        case changesRequestedWithNoReviewRequests
        case changesRequestedWithNilReviewRequests
        case changesRequestedWhenDifferentReviewerReRequested
        case changesRequestedWhenOnlyOneOfTwoReRequested
        case changesRequestedDowngradedWhenReviewerReRequested
        case changesRequestedDowngradedWhenAllReviewersReRequested
        case changesRequestedDowngradedWhenMixedReviewsAndAllChangesReRequesters
        case changesRequestedWithNoLatestReviewsAndPendingRequest
        case changesRequestedWithEmptyLatestReviewsAndPendingRequest
        case changesRequestedWithEmptyLatestReviewsAndNoRequests
        case teamReviewRequestIgnoredGracefully
        case caseInsensitiveRawValue

        var rawValue: String? {
            switch self {
            case .approvedPassesThrough:
                return "APPROVED"
            case .reviewRequiredPassesThrough:
                return "REVIEW_REQUIRED"
            case .nilRawValueReturnsNil:
                return nil
            case .caseInsensitiveRawValue:
                return "changes_requested"
            default:
                return "CHANGES_REQUESTED"
            }
        }

        var latestReviews: [Review]? {
            switch self {
            case .approvedPassesThrough, .reviewRequiredPassesThrough, .nilRawValueReturnsNil,
                    .changesRequestedWithNoLatestReviewsAndPendingRequest:
                return nil
            case .changesRequestedWithEmptyLatestReviewsAndPendingRequest,
                    .changesRequestedWithEmptyLatestReviewsAndNoRequests:
                return []
            case .changesRequestedWhenOnlyOneOfTwoReRequested,
                    .changesRequestedDowngradedWhenAllReviewersReRequested:
                return [
                    ResolveReviewDecisionTests.review("alice", state: "CHANGES_REQUESTED"),
                    ResolveReviewDecisionTests.review("bob", state: "CHANGES_REQUESTED"),
                ]
            case .changesRequestedDowngradedWhenMixedReviewsAndAllChangesReRequesters:
                return [
                    ResolveReviewDecisionTests.review("alice", state: "APPROVED"),
                    ResolveReviewDecisionTests.review("bob", state: "CHANGES_REQUESTED"),
                ]
            default:
                return [ResolveReviewDecisionTests.review("alice", state: "CHANGES_REQUESTED")]
            }
        }

        var reviewRequests: [ReviewRequest]? {
            switch self {
            case .approvedPassesThrough, .reviewRequiredPassesThrough, .nilRawValueReturnsNil:
                return nil
            case .changesRequestedWithNoReviewRequests, .changesRequestedWithEmptyLatestReviewsAndNoRequests:
                return []
            case .changesRequestedWithNilReviewRequests:
                return nil
            case .changesRequestedWhenDifferentReviewerReRequested:
                return [ResolveReviewDecisionTests.request("bob")]
            case .changesRequestedWhenOnlyOneOfTwoReRequested,
                    .changesRequestedDowngradedWhenReviewerReRequested,
                    .caseInsensitiveRawValue:
                return [ResolveReviewDecisionTests.request("alice")]
            case .changesRequestedDowngradedWhenAllReviewersReRequested:
                return [ResolveReviewDecisionTests.request("alice"), ResolveReviewDecisionTests.request("bob")]
            case .changesRequestedDowngradedWhenMixedReviewsAndAllChangesReRequesters:
                return [ResolveReviewDecisionTests.request("bob")]
            case .changesRequestedWithNoLatestReviewsAndPendingRequest,
                    .changesRequestedWithEmptyLatestReviewsAndPendingRequest:
                return [ResolveReviewDecisionTests.request("alice")]
            case .teamReviewRequestIgnoredGracefully:
                return [ReviewRequest(login: nil)]
            }
        }

        var expected: ReviewDecision? {
            switch self {
            case .approvedPassesThrough:
                return .approved
            case .reviewRequiredPassesThrough,
                    .changesRequestedDowngradedWhenReviewerReRequested,
                    .changesRequestedDowngradedWhenAllReviewersReRequested,
                    .changesRequestedDowngradedWhenMixedReviewsAndAllChangesReRequesters,
                    .changesRequestedWithNoLatestReviewsAndPendingRequest,
                    .changesRequestedWithEmptyLatestReviewsAndPendingRequest,
                    .caseInsensitiveRawValue:
                return .reviewRequired
            case .nilRawValueReturnsNil:
                return nil
            default:
                return .changesRequested
            }
        }
    }

    private static func review(_ login: String, state: String) -> Review {
        Review(author: ReviewAuthor(login: login), state: state)
    }

    private static func request(_ login: String) -> ReviewRequest {
        ReviewRequest(login: login)
    }

    @Test(arguments: Scenario.allCases)
    func resolvesReviewDecision(scenario: Scenario) {
        let result = GitHubService.resolveReviewDecision(
            rawValue: scenario.rawValue,
            latestReviews: scenario.latestReviews,
            reviewRequests: scenario.reviewRequests
        )
        #expect(result == scenario.expected)
    }
}

@MainActor
struct ParsePRURLTests {

    @Test(arguments: [
        ("https://github.com/owner/repo/pull/123", "github.com", "owner", "repo", 123),
        ("https://github.example.com/myorg/myrepo/pull/42", "github.example.com", "myorg", "myrepo", 42),
    ] as [(String, String, String, String, Int)])
    func parsesValidPRURL(url: String, host: String, owner: String, repo: String, number: Int) {
        let id = GitHubService.parsePRURL(url)

        #expect(id?.host == host)
        #expect(id?.owner == owner)
        #expect(id?.repo == repo)
        #expect(id?.number == number)
    }

    @Test(arguments: [
        "https://github.com/owner/repo/issues/123",
        "https://github.com/owner/repo/pull/",
        "https://github.com/owner/repo/pull/abc",
        "not-a-url",
        "",
        "https://github.com/owner/repo/pull/123/files",
    ])
    func rejectsInvalidPRURL(url: String) {
        let id = GitHubService.parsePRURL(url)

        #expect(id == nil)
    }
}

@MainActor
struct OtherPRsServiceTests {

    private func makeService() -> OtherPRsService {
        withDependencies {
            $0.userDefaults = UserDefaultsStore.testSuite()
        } operation: {
            OtherPRsService()
        }
    }

    @Test
    func startsEmpty() {
        let service = makeService()
        #expect(service.all().isEmpty)
    }

    @Test
    func addAndContains() {
        let service = makeService()
        let id = makeID()
        service.add(id)
        #expect(service.contains(id))
        #expect(service.all().count == 1)
    }

    @Test
    func addDuplicateIsIdempotent() {
        let service = makeService()
        let id = makeID()
        service.add(id)
        service.add(id)
        #expect(service.all().count == 1)
    }

    @Test
    func removeExisting() {
        let service = makeService()
        let id = makeID()
        service.add(id)
        service.remove(id)
        #expect(!service.contains(id))
        #expect(service.all().isEmpty)
    }

    @Test
    func removeNonExistentIsNoop() {
        let service = makeService()
        service.remove(makeID())
        #expect(service.all().isEmpty)
    }

    @Test
    func addMultiple() {
        let service = makeService()
        service.add(makeID(number: 1))
        service.add(makeID(number: 2))
        service.add(makeID(number: 3))
        #expect(service.all().count == 3)
    }

    @Test
    func clearAll() {
        let service = makeService()
        service.add(makeID(number: 1))
        service.add(makeID(number: 2))
        service.clearAll()
        #expect(service.all().isEmpty)
    }

    private func makeID(number: Int = 1) -> OtherPRIdentifier {
        OtherPRIdentifier(host: "github.com", owner: "owner", repo: "repo", number: number)
    }
}

@MainActor
struct PRTypeDisplayTitleTests {

    @Test(arguments: [0, 1, 5])
    func reviewingSectionNeverPluralized(count: Int) {
        #expect(PRType.reviewing.displayTitle(count: count) == "Awaiting My Review")
    }

    @Test(arguments: [(1, "Other PR"), (0, "Other PRs"), (2, "Other PRs")] as [(Int, String)])
    func otherSectionTitle(count: Int, expected: String) {
        #expect(PRType.other.displayTitle(count: count) == expected)
    }

    @Test(arguments: [(1, "My PR"), (0, "My PRs"), (2, "My PRs")] as [(Int, String)])
    func authoredSectionTitle(count: Int, expected: String) {
        #expect(PRType.authored.displayTitle(count: count) == expected)
    }
}

@MainActor
struct CustomNamesServiceTests {

    private func makeService() -> CustomNamesService {
        withDependencies {
            $0.userDefaults = UserDefaultsStore.testSuite()
        } operation: {
            CustomNamesService()
        }
    }

    @Test
    func startsEmpty() {
        let service = makeService()
        #expect(service.allNames().isEmpty)
    }

    @Test
    func setAndGet() {
        let service = makeService()
        service.setName("My PR", for: "owner/repo#1")
        #expect(service.name(for: "owner/repo#1") == "My PR")
    }

    @Test
    func removeRestoresNil() {
        let service = makeService()
        service.setName("My PR", for: "owner/repo#1")
        service.removeName(for: "owner/repo#1")
        #expect(service.name(for: "owner/repo#1") == nil)
    }

    @Test
    func pruneStaleRemovesInactiveEntries() {
        let service = makeService()
        service.setName("Active PR", for: "owner/repo#1")
        service.setName("Stale PR", for: "owner/repo#2")

        service.pruneStale(keeping: ["owner/repo#1"])

        #expect(service.name(for: "owner/repo#1") == "Active PR")
        #expect(service.name(for: "owner/repo#2") == nil)
    }

    @Test
    func pruneStaleKeepsAllWhenAllActive() {
        let service = makeService()
        service.setName("PR One", for: "owner/repo#1")
        service.setName("PR Two", for: "owner/repo#2")

        service.pruneStale(keeping: ["owner/repo#1", "owner/repo#2"])

        #expect(service.allNames().count == 2)
    }

    @Test
    func pruneStaleWithEmptySetClearsAll() {
        let service = makeService()
        service.setName("PR One", for: "owner/repo#1")

        service.pruneStale(keeping: [])

        #expect(service.allNames().isEmpty)
    }
}

@MainActor
@Suite(.serialized)
struct OtherPRsViewModelTests {

    private func makePR(number: Int, nameWithOwner: String, type: PRType = .other) -> PullRequest {
        let name = String(nameWithOwner.split(separator: "/").last ?? "repo")
        return PullRequest(
            number: number,
            title: "Test PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: name, nameWithOwner: nameWithOwner),
            url: "https://github.com/\(nameWithOwner)/pull/\(number)",
            author: PullRequest.Author(login: "testuser"),
            headRefName: "feature/test",
            updatedAt: Date(),
            buildStatus: .success,
            isWatched: false,
            labels: [],
            type: type,
            isDraft: false,
            statusChecks: [],
            reviewDecision: nil,
            host: "github.com"
        )
    }

    private func makeVM(defaults: UserDefaultsStore? = nil) -> PRMonitorViewModel {
        let defaults = defaults ?? UserDefaultsStore.testSuite()
        return withDependencies {
            $0.userDefaults = defaults
            $0.watchlistService = WatchlistService()
            $0.notificationService = NotificationService()
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = GitHubService()
        } operation: {
            let vm = PRMonitorViewModel(isDemoMode: true)
            vm.stopPolling()
            return vm
        }
    }

    @Test
    func addOtherPRThrowsInvalidURL() async {
        let vm = makeVM()
        do {
            try await vm.addOtherPR(urlString: "not-a-valid-url")
            Issue.record("Expected OtherPRError.invalidURL to be thrown")
        } catch let error as OtherPRError {
            #expect(error == .invalidURL)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test
    func addOtherPRThrowsAlreadyTrackedForAuthoredPR() async {
        let defaults = UserDefaultsStore.testSuite()
        let vm = withDependencies {
            $0.userDefaults = defaults
            $0.watchlistService = WatchlistService()
            $0.notificationService = NotificationService()
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = GitHubService()
        } operation: {
            PRMonitorViewModel(isDemoMode: true)
        }
        for _ in 0..<40 {
            if !vm.authoredPRs.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard let pr = vm.authoredPRs.first else {
            Issue.record("No authored PRs in demo data")
            return
        }

        let url = "https://\(pr.host)/\(pr.repository.nameWithOwner)/pull/\(pr.number)"
        do {
            try await vm.addOtherPR(urlString: url)
            Issue.record("Expected OtherPRError.alreadyTracked to be thrown")
        } catch let error as OtherPRError {
            #expect(error == .alreadyTracked)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test
    func addOtherPRAlreadyTrackedIsCaseInsensitive() async {
        let defaults = UserDefaultsStore.testSuite()
        let vm = withDependencies {
            $0.userDefaults = defaults
            $0.watchlistService = WatchlistService()
            $0.notificationService = NotificationService()
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = GitHubService()
        } operation: {
            PRMonitorViewModel(isDemoMode: true)
        }
        for _ in 0..<40 {
            if !vm.authoredPRs.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard let pr = vm.authoredPRs.first else {
            Issue.record("No authored PRs in demo data")
            return
        }

        let parts = pr.repository.nameWithOwner.split(separator: "/")
        guard parts.count == 2 else {
            Issue.record("Unexpected nameWithOwner format")
            return
        }
        let url = "https://\(pr.host)/\(String(parts[0]).uppercased())/\(String(parts[1]))/pull/\(pr.number)"
        do {
            try await vm.addOtherPR(urlString: url)
            Issue.record("Expected OtherPRError.alreadyTracked to be thrown")
        } catch let error as OtherPRError {
            #expect(error == .alreadyTracked)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test
    func filteredOtherPRsRespectSelectedRepository() {
        let vm = makeVM()

        vm.otherPullRequests = [
            makePR(number: 1, nameWithOwner: "acme/widget"),
            makePR(number: 2, nameWithOwner: "other/project")
        ]

        vm.selectedRepository = "acme/widget"
        #expect(vm.filteredOtherPRs.count == 1)
        #expect(vm.filteredOtherPRs[0].number == 1)

        vm.selectedRepository = "All Repositories"
        #expect(vm.filteredOtherPRs.count == 2)
    }

    @Test
    func removeOtherPRResetsRepoSelectionWhenLastRemoved() {
        let vm = makeVM()

        let pr = makePR(number: 99, nameWithOwner: "acme/widget")
        vm.otherPullRequests = [pr]
        vm.selectedRepository = "acme/widget"

        vm.removeOtherPR(pr)

        #expect(vm.selectedRepository == "All Repositories")
    }

    @Test
    func toggleWatchUpdatesOtherPullRequests() {
        let vm = makeVM()

        var pr = makePR(number: 1, nameWithOwner: "acme/widget")
        pr.isWatched = false
        vm.otherPullRequests = [pr]

        vm.toggleWatch(for: pr)
        #expect(vm.otherPullRequests[0].isWatched == true)

        vm.toggleWatch(for: vm.otherPullRequests[0])
        #expect(vm.otherPullRequests[0].isWatched == false)
    }

    @Test
    func clearAllWatchedResetsOtherPullRequests() {
        let vm = makeVM()

        var pr = makePR(number: 1, nameWithOwner: "acme/widget")
        pr.isWatched = true
        vm.otherPullRequests = [pr]

        vm.clearAllWatched()

        #expect(vm.otherPullRequests[0].isWatched == false)
    }

    @Test
    func removeOtherPRClearsCustomName() {
        let defaults = UserDefaultsStore.testSuite()
        let customNames = withDependencies {
            $0.userDefaults = defaults
        } operation: {
            CustomNamesService()
        }
        let vm = withDependencies {
            $0.userDefaults = defaults
            $0.watchlistService = WatchlistService()
            $0.notificationService = NotificationService()
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = customNames
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = GitHubService()
        } operation: {
            let vm = PRMonitorViewModel(isDemoMode: true)
            vm.stopPolling()
            return vm
        }

        let pr = makePR(number: 99, nameWithOwner: "acme/widget")
        vm.otherPullRequests = [pr]

        vm.renamePR(pr, to: "Custom Name")

        vm.removeOtherPR(pr)

        #expect(customNames.name(for: pr.id) == nil)
    }

    @Test
    func removeOtherPRKeepsRepoSelectionWhenOthersRemain() {
        let vm = makeVM()

        let pr1 = makePR(number: 1, nameWithOwner: "acme/widget")
        let pr2 = makePR(number: 2, nameWithOwner: "acme/widget")
        vm.otherPullRequests = [pr1, pr2]
        vm.selectedRepository = "acme/widget"

        vm.removeOtherPR(pr1)

        #expect(vm.selectedRepository == "acme/widget")
    }
}

@MainActor
@Suite(.serialized)
struct PRMonitorViewModelTests {

    private func makePR(number: Int = 1, nameWithOwner: String = "acme/widget", buildStatus: BuildStatus) -> PullRequest {
        let name = String(nameWithOwner.split(separator: "/").last ?? "repo")
        return PullRequest(
            number: number,
            title: "Test PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: name, nameWithOwner: nameWithOwner),
            url: "https://github.com/\(nameWithOwner)/pull/\(number)",
            author: PullRequest.Author(login: "testuser"),
            headRefName: "feature/test",
            updatedAt: Date(),
            buildStatus: buildStatus,
            isWatched: false,
            labels: [],
            type: .authored,
            isDraft: false,
            statusChecks: [],
            reviewDecision: nil,
            host: "github.com"
        )
    }

    private func makePR(number: Int, nameWithOwner: String, type: PRType = .other, updatedAt: Date = Date()) -> PullRequest {
        let name = String(nameWithOwner.split(separator: "/").last ?? "repo")
        return PullRequest(
            number: number,
            title: "Test PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: name, nameWithOwner: nameWithOwner),
            url: "https://github.com/\(nameWithOwner)/pull/\(number)",
            author: PullRequest.Author(login: "testuser"),
            headRefName: "feature/test",
            updatedAt: updatedAt,
            buildStatus: .success,
            isWatched: false,
            labels: [],
            type: type,
            isDraft: false,
            statusChecks: [],
            reviewDecision: nil,
            host: "github.com"
        )
    }

    private func createLoadedViewModel(defaults: UserDefaultsStore? = nil) async -> PRMonitorViewModel {
        let d = defaults ?? UserDefaultsStore.testSuite()
        let vm = withDependencies {
            $0.userDefaults = d
            $0.watchlistService = WatchlistService()
            $0.notificationService = NotificationService()
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = GitHubService()
        } operation: {
            PRMonitorViewModel(isDemoMode: true)
        }
        for _ in 0..<40 {
            if !vm.authoredPRs.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return vm
    }

    private func makeVM() -> PRMonitorViewModel {
        let defaults = UserDefaultsStore.testSuite()
        return withDependencies {
            $0.userDefaults = defaults
            $0.watchlistService = WatchlistService()
            $0.notificationService = NotificationService()
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = GitHubService()
        } operation: {
            let vm = PRMonitorViewModel(isDemoMode: true)
            vm.stopPolling()
            return vm
        }
    }

    @Test
    func availableRepositories() async {
        let vm = await createLoadedViewModel()

        let repos = vm.availableRepositories
        #expect(repos.count == 2)
        #expect(repos == ["feline-federation/cat-show-tracker", "fromagerie/cheese-cellar-manager"])
    }

    @Test
    func defaultSelectedRepository() async {
        let vm = await createLoadedViewModel()

        #expect(vm.selectedRepository == "All Repositories")
    }

    @Test
    func reposWithIssuesIncludesNotStartedPRs() {
        let vm = makeVM()

        vm.otherPullRequests = [makePR(buildStatus: .notStarted)]

        #expect(vm.reposWithIssues == ["acme/widget"])
    }

    @Test
    func watchlistReportsCompletionFromNotStarted() {
        let watchlist = withDependencies {
            $0.userDefaults = UserDefaultsStore.testSuite()
        } operation: {
            WatchlistService()
        }
        let pendingPR = makePR(buildStatus: .notStarted)
        var completedPR = pendingPR
        completedPR.buildStatus = .success

        watchlist.watch(pendingPR)

        #expect(watchlist.checkForCompletions(currentPRs: [completedPR]).map(\.id) == [pendingPR.id])
    }

    @Test
    func filterByRepository() async {
        let vm = await createLoadedViewModel()

        vm.selectedRepository = "fromagerie/cheese-cellar-manager"

        #expect(!vm.authoredPRs.isEmpty)
        #expect(vm.authoredPRs.allSatisfy { $0.repository.nameWithOwner == "fromagerie/cheese-cellar-manager" })

        #expect(vm.reviewPRs.isEmpty)
    }

    @Test
    func filterByRepositoryShowsReviewPRs() async {
        let vm = await createLoadedViewModel()

        vm.selectedRepository = "feline-federation/cat-show-tracker"

        #expect(!vm.reviewPRs.isEmpty)
        #expect(vm.reviewPRs.allSatisfy { $0.repository.nameWithOwner == "feline-federation/cat-show-tracker" })

        #expect(vm.authoredPRs.isEmpty)
    }

    @Test
    func allRepositoriesShowsEverything() async {
        let defaults = UserDefaultsStore.testSuite()
        defaults.set(false, forKey: .hideInactivePRs)
        let vm = await createLoadedViewModel(defaults: defaults)

        vm.selectedRepository = "All Repositories"

        let totalPRs = vm.authoredPRs.count + vm.reviewPRs.count
        #expect(totalPRs == 8)
    }

    @Test
    func selectedRepoResetOnRefresh() async {
        let vm = await createLoadedViewModel()

        vm.selectedRepository = "feline-federation/cat-show-tracker"
        #expect(vm.selectedRepository == "feline-federation/cat-show-tracker")

        vm.selectedRepository = "nonexistent/repo"

        await vm.refresh()
        #expect(vm.selectedRepository == "All Repositories")
    }

    @Test
    func renamePRUpdatesDisplayTitleInMemory() async {
        let vm = await createLoadedViewModel()

        guard let pr = vm.authoredPRs.first else {
            Issue.record("No authored PRs in demo data")
            return
        }

        vm.renamePR(pr, to: "My Custom Name")

        let updated = vm.authoredPRs.first { $0.id == pr.id }
        #expect(updated?.customName == "My Custom Name")
        #expect(updated?.displayTitle == "My Custom Name")
        #expect(updated?.title == pr.title)
    }

    @Test
    func renamePRNilRestoresGitHubTitle() async {
        let vm = await createLoadedViewModel()

        guard let pr = vm.authoredPRs.first else {
            Issue.record("No authored PRs in demo data")
            return
        }

        vm.renamePR(pr, to: "Temporary Name")
        vm.renamePR(pr, to: nil)

        let updated = vm.authoredPRs.first { $0.id == pr.id }
        #expect(updated?.customName == nil)
        #expect(updated?.displayTitle == pr.title)
    }

    @Test
    func renamePREmptyStringActsAsNil() async {
        let vm = await createLoadedViewModel()

        guard let pr = vm.authoredPRs.first else {
            Issue.record("No authored PRs in demo data")
            return
        }

        vm.renamePR(pr, to: "Temporary Name")
        vm.renamePR(pr, to: "")

        let updated = vm.authoredPRs.first { $0.id == pr.id }
        #expect(updated?.customName == nil)
        #expect(updated?.displayTitle == pr.title)
    }

    @Test
    func sortPutsChangesRequestedFirst() async {
        let defaults = UserDefaultsStore.testSuite()
        defaults.set(true, forKey: .sortNonSuccessFirst)
        let vm = await createLoadedViewModel(defaults: defaults)

        let authored = vm.authoredPRs
        let changesRequestedIndex = authored.firstIndex(where: { $0.reviewDecision == .changesRequested })
        let pureSuccessIndex = authored.firstIndex(where: { $0.buildStatus == .success && $0.reviewDecision == nil })

        if let crIdx = changesRequestedIndex, let psIdx = pureSuccessIndex {
            #expect(crIdx < psIdx)
        }
    }

    // MARK: - Hide Inactive PRs

    @Test
    func inactivePRsVisibleByDefault() async {
        let vm = await createLoadedViewModel()

        let authoredInactive = vm.authoredPRs.filter { $0.buildStatus == .inactive }
        #expect(!authoredInactive.isEmpty, "Inactive PRs should be visible when hideInactivePRs is off")
    }

    @Test
    func hideInactivePRsFiltersInactiveFromAuthored() async {
        let defaults = UserDefaultsStore.testSuite()
        defaults.set(true, forKey: .hideInactivePRs)
        let vm = await createLoadedViewModel(defaults: defaults)

        let authoredInactive = vm.authoredPRs.filter { $0.buildStatus == .inactive }
        #expect(authoredInactive.isEmpty, "Inactive authored PRs should be hidden when hideInactivePRs is on")
    }

    @Test
    func hideInactivePRsDoesNotFilterReviewPRs() async {
        let defaults = UserDefaultsStore.testSuite()
        defaults.set(true, forKey: .enableInactiveBranchDetection)
        defaults.set(true, forKey: .hideInactivePRs)
        defaults.set(3, forKey: .inactiveBranchThresholdDays)
        let vm = await createLoadedViewModel(defaults: defaults)

        let allReview = vm.reviewPRs
        #expect(!allReview.isEmpty, "Review PRs should still appear when hideInactivePRs is on")
    }

    private func makeVMWithDefaults(_ configure: (UserDefaultsStore) -> Void) -> PRMonitorViewModel {
        let defaults = UserDefaultsStore.testSuite()
        configure(defaults)
        return withDependencies {
            $0.userDefaults = defaults
            $0.watchlistService = WatchlistService()
            $0.notificationService = NotificationService()
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = GitHubService()
        } operation: {
            let vm = PRMonitorViewModel(isDemoMode: false)
            vm.stopPolling()
            return vm
        }
    }

    @Test
    func hideInactivePRsFiltersInactiveFromOtherPRs() {
        let vm = makeVMWithDefaults { defaults in
            defaults.set(true, forKey: .enableInactiveBranchDetection)
            defaults.set(true, forKey: .hideInactivePRs)
            defaults.set(3, forKey: .inactiveBranchThresholdDays)
        }

        var inactivePR = makePR(number: 1, nameWithOwner: "acme/widget", updatedAt: Date().addingTimeInterval(-4 * 24 * 60 * 60))
        inactivePR.buildStatus = .inactive
        var successPR = makePR(number: 2, nameWithOwner: "acme/widget")
        successPR.buildStatus = .success

        vm.otherPullRequests = [inactivePR, successPR]

        #expect(vm.filteredOtherPRs.count == 1, "Inactive PR should be hidden from other PRs")
        #expect(vm.filteredOtherPRs[0].buildStatus == .success)
    }

    @Test
    func hideInactivePRsHidesStaleConflictPR() {
        let vm = makeVMWithDefaults { defaults in
            defaults.set(true, forKey: .enableInactiveBranchDetection)
            defaults.set(true, forKey: .hideInactivePRs)
            defaults.set(3, forKey: .inactiveBranchThresholdDays)
        }

        var staleConflictPR = makePR(number: 1, nameWithOwner: "acme/widget", updatedAt: Date().addingTimeInterval(-4 * 24 * 60 * 60))
        staleConflictPR.buildStatus = .conflict

        vm.otherPullRequests = [staleConflictPR]

        #expect(vm.filteredOtherPRs.isEmpty, "Stale PR with conflict status should be hidden when hideInactivePRs is on")
    }

    @Test
    func hideInactivePRsDoesNotHideActiveConflictPR() {
        let vm = makeVMWithDefaults { defaults in
            defaults.set(true, forKey: .enableInactiveBranchDetection)
            defaults.set(true, forKey: .hideInactivePRs)
            defaults.set(3, forKey: .inactiveBranchThresholdDays)
        }

        var activeConflictPR = makePR(number: 1, nameWithOwner: "acme/widget", updatedAt: Date())
        activeConflictPR.buildStatus = .conflict

        vm.otherPullRequests = [activeConflictPR]

        #expect(vm.filteredOtherPRs.count == 1, "Recently-updated conflict PR should not be hidden")
    }

    @Test
    func hideInactivePRsExcludesInactiveFromReposWithIssues() {
        let vm = makeVMWithDefaults { defaults in
            defaults.set(true, forKey: .enableInactiveBranchDetection)
            defaults.set(true, forKey: .hideInactivePRs)
            defaults.set(3, forKey: .inactiveBranchThresholdDays)
        }

        var successPR = makePR(number: 999, nameWithOwner: "acme/success-only")
        successPR.buildStatus = .success

        var inactivePR = makePR(number: 1, nameWithOwner: "acme/widget", updatedAt: Date().addingTimeInterval(-4 * 24 * 60 * 60))
        inactivePR.buildStatus = .inactive

        vm.otherPullRequests = [successPR, inactivePR]

        #expect(!vm.reposWithIssues.contains("acme/widget"), "Repo with only inactive PR should not show issues when hidden")
    }

    @Test
    func hideInactivePRsOffStillShowsInactiveInReposWithIssues() {
        let vm = makeVMWithDefaults { defaults in
            defaults.set(false, forKey: .hideInactivePRs)
        }

        var inactivePR = makePR(number: 1, nameWithOwner: "acme/widget")
        inactivePR.buildStatus = .inactive

        vm.otherPullRequests = [inactivePR]

        #expect(vm.reposWithIssues.contains("acme/widget"), "Repo with inactive PR shows issues when hideInactivePRs is off")
    }

    @Test
    func hideInactivePRsDoesNotAffectSuccessPRs() async {
        let defaults = UserDefaultsStore.testSuite()
        defaults.set(true, forKey: .hideInactivePRs)
        let vm = await createLoadedViewModel(defaults: defaults)

        let authoredSuccess = vm.authoredPRs.filter { $0.buildStatus == .success }
        #expect(!authoredSuccess.isEmpty, "Success PRs should still be visible when hideInactivePRs is on")
    }

    @Test
    func availableRepositoriesStillIncludesInactivePRReposWhenHidden() async {
        let defaults = UserDefaultsStore.testSuite()
        defaults.set(true, forKey: .hideInactivePRs)
        let vm = await createLoadedViewModel(defaults: defaults)

        let repos = vm.availableRepositories
        #expect(repos.count == 2, "Repo list should still include all repos even when inactive PRs are hidden")
    }
}
