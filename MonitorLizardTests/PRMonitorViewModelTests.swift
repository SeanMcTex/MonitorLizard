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

        // The demo data also gives this repo a reviewing stack (demo-stack-camembert),
        // so review PRs may exist here — but they must all belong to this repo.
        #expect(vm.reviewPRs.allSatisfy { $0.repository.nameWithOwner == "fromagerie/cheese-cellar-manager" })
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

    // MARK: - Stacked PRs

    @Test
    func sectionRowsRenderAStackAsOneBlock() {
        let vm = makeVM()

        var basePR = makePR(number: 1, nameWithOwner: "acme/widget")
        basePR.stack = PRStackInfo(id: "ST_stack", number: 3, size: 2, position: 1)
        var topPR = makePR(number: 2, nameWithOwner: "acme/widget")
        topPR.stack = PRStackInfo(id: "ST_stack", number: 3, size: 2, position: 2)

        vm.otherPullRequests = [basePR, topPR]

        let rows = vm.sectionRows(for: .other)

        #expect(rows.count == 3)
        guard case .stackHeader(let header) = rows.first else {
            Issue.record("Expected a stack header first")
            return
        }
        #expect(header.number == 3)
        #expect(rows.compactMap(\.pr).map(\.number) == [1, 2])
        #expect(vm.filteredOtherPRs.map(\.number) == [1, 2])
    }

    @Test
    func stackPartsAreInMergeOrder() {
        let vm = makeVM()

        var part2 = makePR(number: 2, nameWithOwner: "acme/widget")
        part2.stack = PRStackInfo(id: "ST_stack", number: 3, size: 2, position: 2)
        var part1 = makePR(number: 1, nameWithOwner: "acme/widget")
        part1.stack = PRStackInfo(id: "ST_stack", number: 3, size: 2, position: 1)

        vm.otherPullRequests = [part2, part1]

        #expect(vm.stackParts(inStack: "ST_stack").map(\.number) == [1, 2])
        #expect(vm.stackParts(inStack: "unknown").isEmpty)
    }

    @Test
    func collapsingAStackHidesItsPartsWithoutChangingCounts() {
        let vm = makeVM()

        var basePR = makePR(number: 1, nameWithOwner: "acme/widget")
        basePR.stack = PRStackInfo(id: "ST_stack", number: 3, size: 2, position: 1)
        var topPR = makePR(number: 2, nameWithOwner: "acme/widget")
        topPR.stack = PRStackInfo(id: "ST_stack", number: 3, size: 2, position: 2)

        vm.otherPullRequests = [basePR, topPR]

        vm.toggleStackCollapse("ST_stack")
        #expect(vm.isStackCollapsed("ST_stack"))
        #expect(vm.sectionRows(for: .other).count == 1)
        #expect(vm.filteredOtherPRs.map(\.number) == [1, 2], "Collapsing must not change counts")

        vm.toggleStackCollapse("ST_stack")
        #expect(!vm.isStackCollapsed("ST_stack"))
        #expect(vm.sectionRows(for: .other).count == 3)
    }

    @Test
    func toggleWatchWatchesEveryKnownStackMember() {
        let vm = makeVM()

        var part1 = makePR(number: 1, nameWithOwner: "acme/widget")
        part1.stack = PRStackInfo(id: "ST_stack", number: 3, size: 2, position: 1)
        var part2 = makePR(number: 2, nameWithOwner: "acme/widget")
        part2.stack = PRStackInfo(id: "ST_stack", number: 3, size: 2, position: 2)

        vm.otherPullRequests = [part2, part1]
        #expect(vm.stackMemberCount(for: part1) == 2)

        vm.toggleWatch(for: part1)

        #expect(vm.otherPullRequests.allSatisfy { $0.isWatched })
        #expect(vm.stackMemberCount(for: part2) == 2)

        vm.toggleWatch(for: vm.otherPullRequests[0])

        #expect(vm.otherPullRequests.allSatisfy { !$0.isWatched })
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
            // Stub the service so the poll started by init cannot reach the
            // unimplemented shell executor; its recorded issue would be attributed
            // to whichever test is running when that task fires.
            $0[GitHubServiceKey.self] = StubGitHubService()
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

@MainActor
private final class StubGitHubService: GitHubServicing {
    var result = PRFetchResult(pullRequests: [], isPartial: false)
    /// Pinned Other PRs returned by `fetchOtherPR`, matched by repository and
    /// number.
    var otherPRResults: [PullRequest] = []
    /// Number of times `fetchMissingStackParts` has been called.
    var fetchMissingStackPartsCallCount = 0
    /// The identifying arguments of every `fetchMissingStackParts` call, in
    /// order, so tests can assert what the ViewModel passed to the service.
    var fetchMissingStackPartsCalls: [FetchMissingStackPartsCall] = []

    struct FetchMissingStackPartsCall {
        let stackID: String
        let host: String
        let owner: String
        let repo: String
        let type: PRType
    }

    func checkGHAvailable() async throws {}
    func invalidateHostsCache() {}

    func fetchAllOpenPRs(enableInactiveDetection: Bool, inactiveThresholdDays: Int, isDemoMode: Bool) async throws -> PRFetchResult {
        result
    }

    func fetchPRStatus(owner: String, repo: String, number: Int, updatedAt: Date, enableInactiveDetection: Bool, inactiveThresholdDays: Int, host: String) async throws -> (status: BuildStatus, headRefName: String, statusChecks: [StatusCheck], reviewDecision: ReviewDecision?) {
        (.success, "", [], nil)
    }

    func fetchOtherPR(_ id: OtherPRIdentifier, enableInactiveDetection: Bool, inactiveThresholdDays: Int) async throws -> PullRequest? {
        let nameWithOwner = "\(id.owner)/\(id.repo)"
        return otherPRResults.first {
            $0.number == id.number && $0.repository.nameWithOwner == nameWithOwner
        }
    }

    var stackParts: [PullRequest] = []
    var stackMergedPositions: [Int] = []
    /// When set, the next `fetchMissingStackParts` call suspends on this gate
    /// until the test releases it, then fails with the released error. The gate
    /// is consumed by that first call.
    var lookupGate: StackLookupGate?
    /// When set, `fetchMissingStackParts` throws this error, simulating a
    /// transient stack completion failure.
    var stackPartsError: (any Error)?

    func fetchMissingStackParts(
        stackID: String,
        host: String,
        owner: String,
        repo: String,
        knownNumbers: Set<Int>,
        type: PRType,
        enableInactiveDetection: Bool,
        inactiveThresholdDays: Int
    ) async throws -> StackCompletion {
        fetchMissingStackPartsCallCount += 1
        fetchMissingStackPartsCalls.append(
            FetchMissingStackPartsCall(
                stackID: stackID,
                host: host,
                owner: owner,
                repo: repo,
                type: type
            )
        )
        if let lookupGate {
            self.lookupGate = nil
            try await lookupGate.hold()
        }
        if let stackPartsError {
            throw stackPartsError
        }
        return StackCompletion(
            missingParts: stackParts.filter { !knownNumbers.contains($0.number) },
            mergedPositions: stackMergedPositions
        )
    }
}

/// A stand-in for the transient lookup failures `fetchMissingStackParts` can hit.
private struct TransientStackLookupError: Error {}

/// A deterministic gate for a stack completion lookup: a gated lookup suspends
/// until `release(throwing:)` and then fails with that error. A release that
/// lands before the lookup registers is still honored, so a test that acts on
/// the VM while the lookup is in flight never depends on scheduling. Release
/// is idempotent — the first one wins — so a fallback release does not fight
/// the test's explicit release.
private final class StackLookupGate: @unchecked Sendable {
    private let lock = NSLock()
    private var holdWaiter: CheckedContinuation<Void, any Error>?
    private var releasedError: (any Error)?
    private var isReleased = false

    /// The gated lookup: suspends until release, then throws the released error.
    func hold() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            lock.lock()
            if let releasedError {
                lock.unlock()
                continuation.resume(throwing: releasedError)
            } else {
                holdWaiter = continuation
                lock.unlock()
            }
        }
    }

    /// Releases the held lookup, failing it with `error`.
    func release(throwing error: any Error) {
        lock.lock()
        if isReleased {
            lock.unlock()
            return
        }
        isReleased = true
        releasedError = error
        let waiter = holdWaiter
        holdWaiter = nil
        lock.unlock()
        waiter?.resume(throwing: error)
    }
}

/// A notification service that does nothing, for VM setups that do not test
/// notification delivery: initialization would otherwise ask the system for
/// notification authorization.
private struct NoopNotificationService: NotificationServicing {
    func requestAuthorization() async throws {}
    func notifyBuildComplete(pr: PullRequest, status: BuildStatus) {}
    func notifyStackReady(stack: ReadyStack) {}
}

/// Waits until the VM's initial refresh has published its state. Records an
/// issue if it never finishes, so a stalled setup fails the test explicitly
/// instead of leaving it to assert against unwritten state.
@MainActor
private func waitForInitialRefresh(_ vm: PRMonitorViewModel) async {
    for _ in 0..<200 {
        if vm.lastRefreshTime != nil { return }
        try? await Task.sleep(for: .milliseconds(25))
    }
    Issue.record("The VM's initial refresh did not finish; setup state was never written")
}

private final class StackReadySpy: NotificationServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ReadyStack] = []

    func requestAuthorization() async throws {}

    func notifyBuildComplete(pr: PullRequest, status: BuildStatus) {}

    func notifyStackReady(stack: ReadyStack) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(stack)
    }

    var notifications: [ReadyStack] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

@MainActor
@Suite(.serialized)
struct StackWatchNotificationTests {

    private func makeStackedPR(
        _ number: Int,
        position: Int,
        status: BuildStatus,
        stackSize: Int = 2
    ) -> PullRequest {
        PullRequest(
            number: number,
            title: "PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: "repo", nameWithOwner: "owner/repo"),
            url: "https://github.com/owner/repo/pull/\(number)",
            author: PullRequest.Author(login: "alice"),
            headRefName: "feature/\(number)",
            updatedAt: Date(),
            buildStatus: status,
            isWatched: false,
            labels: [],
            type: .authored,
            isDraft: false,
            statusChecks: [],
            reviewDecision: nil,
            host: "github.com",
            stack: PRStackInfo(id: "ST_stack", number: 42, size: stackSize, position: position)
        )
    }

    @Test
    func notifiesOnceWhenAWatchedStackBecomesReady() async {
        let stub = StubGitHubService()
        let spy = StackReadySpy()
        let vm = withDependencies {
            $0.userDefaults = UserDefaultsStore.testSuite()
            $0.watchlistService = WatchlistService()
            $0.notificationService = spy
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = stub
        } operation: {
            PRMonitorViewModel(isDemoMode: false)
        }
        vm.stopPolling()
        // Let the poll started by init finish so only the refreshes below drive the spy.
        await waitForInitialRefresh(vm)

        stub.result = PRFetchResult(pullRequests: [
            makeStackedPR(1, position: 1, status: .pending),
            makeStackedPR(2, position: 2, status: .pending),
        ], isPartial: false)
        await vm.refresh()

        stub.result = PRFetchResult(pullRequests: [
            makeStackedPR(1, position: 1, status: .success),
            makeStackedPR(2, position: 2, status: .success),
        ], isPartial: false)
        await vm.refresh()
        #expect(spy.notifications.isEmpty, "An unwatched stack must not notify")

        guard let pr = vm.authoredPRs.first else {
            Issue.record("Expected authored stack PRs")
            return
        }
        vm.toggleWatch(for: pr)
        #expect(vm.authoredPRs.allSatisfy { $0.isWatched })

        await vm.refresh()
        #expect(spy.notifications == [.init(
            id: "ST_stack",
            number: 42,
            size: 2,
            allReady: true,
            nextPartPosition: 1,
            landedPositions: []
        )])

        await vm.refresh()
        #expect(spy.notifications.count == 1, "A ready stack must only notify once")
    }

    @Test
    func notifiesTheNextPartWhenLowerPartsHaveAlreadyMerged() async {
        let stub = StubGitHubService()
        let spy = StackReadySpy()
        let vm = withDependencies {
            $0.userDefaults = UserDefaultsStore.testSuite()
            $0.watchlistService = WatchlistService()
            $0.notificationService = spy
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = stub
        } operation: {
            // Watching after the first lookup requires a fresh resolution before
            // readiness can notify; do not reuse the earlier companion status.
            PRMonitorViewModel(isDemoMode: false, stackResolutionTTL: 0)
        }
        vm.stopPolling()
        // Let the poll started by init finish so only the refreshes below drive the spy.
        await waitForInitialRefresh(vm)

        // Part 1 has already merged, so part 2 of 3 is the one to merge next.
        stub.result = PRFetchResult(pullRequests: [
            makeStackedPR(2, position: 2, status: .success, stackSize: 3),
        ], isPartial: false)
        stub.stackMergedPositions = [1]
        await vm.refresh()
        #expect(spy.notifications.isEmpty, "An unwatched stack must not notify")

        guard let pr = vm.authoredPRs.first else {
            Issue.record("Expected an authored stack PR")
            return
        }
        vm.toggleWatch(for: pr)
        #expect(vm.authoredPRs.allSatisfy { $0.isWatched })

        await vm.refresh()
        #expect(spy.notifications == [.init(
            id: "ST_stack",
            number: 42,
            size: 3,
            allReady: false,
            nextPartPosition: 2,
            landedPositions: [1]
        )])
    }

    @Test
    func cachedCompanionStatusDefersNotificationAndPreservesReadyHistory() async throws {
        let stub = StubGitHubService()
        stub.result = PRFetchResult(pullRequests: [
            makeStackedPR(1, position: 1, status: .pending, stackSize: 3),
        ], isPartial: false)
        stub.stackParts = [
            makeStackedPR(2, position: 2, status: .success, stackSize: 3),
            makeStackedPR(3, position: 3, status: .success, stackSize: 3),
        ]
        let spy = StackReadySpy()
        let vm = withDependencies {
            $0.userDefaults = UserDefaultsStore.testSuite()
            $0.watchlistService = WatchlistService()
            $0.notificationService = spy
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = stub
        } operation: {
            PRMonitorViewModel(isDemoMode: false)
        }
        vm.stopPolling()
        await waitForInitialRefresh(vm)
        #expect(stub.fetchMissingStackPartsCallCount == 1)

        let anchor = try #require(vm.authoredPRs.first { $0.number == 1 })
        vm.toggleWatch(for: anchor)
        stub.result = PRFetchResult(pullRequests: [
            makeStackedPR(1, position: 1, status: .success, stackSize: 3),
        ], isPartial: false)
        await vm.refresh()
        #expect(stub.fetchMissingStackPartsCallCount == 1, "the lookup was reused rather than refreshed")
        #expect(spy.notifications.isEmpty, "cached green companions must not generate a ready notification")

        // Changing the searched set forces a fresh lookup; only then may it notify.
        stub.result = PRFetchResult(pullRequests: [
            makeStackedPR(1, position: 1, status: .success, stackSize: 3),
            makeStackedPR(2, position: 2, status: .success, stackSize: 3),
        ], isPartial: false)
        await vm.refresh()
        #expect(stub.fetchMissingStackPartsCallCount == 2)
        #expect(spy.notifications.count == 1)
        #expect(spy.notifications.first?.nextPartPosition == 1)

        // Reusing that result must not erase the already-ready membership; a
        // subsequent fresh lookup of the same ready stack must not re-notify.
        await vm.refresh()
        #expect(stub.fetchMissingStackPartsCallCount == 2)
        stub.result = PRFetchResult(pullRequests: [
            makeStackedPR(1, position: 1, status: .success, stackSize: 3),
        ], isPartial: false)
        await vm.refresh()
        #expect(stub.fetchMissingStackPartsCallCount == 3)
        #expect(spy.notifications.count == 1)
    }

    @Test
    func failedRevalidationDefersNotificationUntilTheLookupRecovers() async throws {
        let stub = StubGitHubService()
        stub.result = PRFetchResult(pullRequests: [
            makeStackedPR(1, position: 1, status: .pending),
        ], isPartial: false)
        stub.stackParts = [makeStackedPR(2, position: 2, status: .success)]
        let spy = StackReadySpy()
        let vm = withDependencies {
            $0.userDefaults = UserDefaultsStore.testSuite()
            $0.watchlistService = WatchlistService()
            $0.notificationService = spy
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = stub
        } operation: {
            PRMonitorViewModel(isDemoMode: false, stackResolutionTTL: 0)
        }
        vm.stopPolling()
        await waitForInitialRefresh(vm)

        let anchor = try #require(vm.authoredPRs.first { $0.number == 1 })
        vm.toggleWatch(for: anchor)
        stub.result = PRFetchResult(pullRequests: [
            makeStackedPR(1, position: 1, status: .success),
        ], isPartial: false)
        stub.stackPartsError = TransientStackLookupError()
        await vm.refresh()
        #expect(stub.fetchMissingStackPartsCallCount == 2)
        #expect(spy.notifications.isEmpty, "a failed revalidation cannot establish readiness")

        stub.stackPartsError = nil
        await vm.refresh()
        #expect(stub.fetchMissingStackPartsCallCount == 3)
        #expect(spy.notifications.count == 1, "fresh resolution must resume readiness evaluation")
    }

    @Test
    func refreshDoesNotOverlapASuspendedStackLookup() async {
        let stub = StubGitHubService()
        let spy = StackReadySpy()
        let vm = withDependencies {
            $0.userDefaults = UserDefaultsStore.testSuite()
            $0.watchlistService = WatchlistService()
            $0.notificationService = spy
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = stub
        } operation: {
            PRMonitorViewModel(isDemoMode: false)
        }
        vm.stopPolling()
        await waitForInitialRefresh(vm)

        let base = makeStackedPR(1, position: 1, status: .success)
        stub.result = PRFetchResult(pullRequests: [base], isPartial: false)
        stub.stackParts = [makeStackedPR(2, position: 2, status: .success)]
        vm.toggleWatch(for: base)
        let lastRefreshTime = vm.lastRefreshTime

        let gate = StackLookupGate()
        stub.lookupGate = gate
        defer { gate.release(throwing: TransientStackLookupError()) }
        let firstRefresh = Task { await vm.refresh() }
        for _ in 0..<200 {
            if stub.fetchMissingStackPartsCallCount == 1 { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard stub.fetchMissingStackPartsCallCount == 1 else {
            Issue.record("The first completion lookup never started")
            gate.release(throwing: TransientStackLookupError())
            await firstRefresh.value
            return
        }
        #expect(vm.isLoading, "the first refresh must still be suspended")

        // Without a single-flight guard this second call resolves the same green
        // stack while the first lookup is held and notifies from the racing result.
        await vm.refresh()
        #expect(stub.fetchMissingStackPartsCallCount == 1)
        #expect(vm.lastRefreshTime == lastRefreshTime, "a rejected refresh must not publish")
        #expect(vm.isLoading, "the held refresh still owns the loading state")
        #expect(spy.notifications.isEmpty)

        gate.release(throwing: TransientStackLookupError())
        await firstRefresh.value
        #expect(!vm.isLoading)
        #expect(spy.notifications.isEmpty)

        await vm.refresh()
        #expect(stub.fetchMissingStackPartsCallCount == 2, "a new refresh can resolve after the first finishes")
        #expect(spy.notifications.count == 1)
    }

    @Test
    func doesNotReNotifyAnAlreadyReadyWatchedStackAfterRelaunch() async {
        let defaults = UserDefaultsStore.testSuite()
        let stub = StubGitHubService()
        let firstSpy = StackReadySpy()
        let firstVM = withDependencies {
            $0.userDefaults = defaults
            $0.watchlistService = WatchlistService()
            $0.notificationService = firstSpy
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = stub
        } operation: {
            PRMonitorViewModel(isDemoMode: false)
        }
        firstVM.stopPolling()
        // Let the poll started by init finish so only the refreshes below drive the spy.
        await waitForInitialRefresh(firstVM)

        stub.result = PRFetchResult(pullRequests: [
            makeStackedPR(1, position: 1, status: .success),
            makeStackedPR(2, position: 2, status: .success),
        ], isPartial: false)
        await firstVM.refresh()
        #expect(firstSpy.notifications.isEmpty, "An unwatched stack must not notify")

        guard let pr = firstVM.authoredPRs.first else {
            Issue.record("Expected authored stack PRs")
            return
        }
        firstVM.toggleWatch(for: pr)
        await firstVM.refresh()
        #expect(firstSpy.notifications.count == 1)

        // A freshly constructed VM over the same defaults plays the role of a
        // relaunch: it must not notify again for the already-ready watched stack.
        let secondSpy = StackReadySpy()
        let secondVM = withDependencies {
            $0.userDefaults = defaults
            $0.watchlistService = WatchlistService()
            $0.notificationService = secondSpy
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = stub
        } operation: {
            PRMonitorViewModel(isDemoMode: false)
        }
        secondVM.stopPolling()
        // Wait for the initial refresh the relaunched VM schedules itself.
        await waitForInitialRefresh(secondVM)

        #expect(secondSpy.notifications.isEmpty, "An already-ready watched stack must not notify again after relaunch")
    }

    @Test
    func partialFetchDoesNotDropAReadyWatchedStack() async {
        let stub = StubGitHubService()
        let spy = StackReadySpy()
        let vm = withDependencies {
            $0.userDefaults = UserDefaultsStore.testSuite()
            $0.watchlistService = WatchlistService()
            $0.notificationService = spy
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = stub
        } operation: {
            PRMonitorViewModel(isDemoMode: false)
        }
        vm.stopPolling()
        // Let the poll started by init finish so only the refreshes below drive the spy.
        await waitForInitialRefresh(vm)

        stub.result = PRFetchResult(pullRequests: [
            makeStackedPR(1, position: 1, status: .success),
            makeStackedPR(2, position: 2, status: .success),
        ], isPartial: false)
        await vm.refresh()
        guard let pr = vm.authoredPRs.first else {
            Issue.record("Expected authored stack PRs")
            return
        }
        vm.toggleWatch(for: pr)
        await vm.refresh()
        #expect(spy.notifications.count == 1)

        // A partial fetch that omits the stack entirely (one host's search failed)
        // must not be read as "no longer ready": the ready set must survive it.
        stub.result = PRFetchResult(pullRequests: [], isPartial: true)
        await vm.refresh()
        #expect(spy.notifications.count == 1)

        // The next full refresh shows the stack ready again; it must not re-notify.
        stub.result = PRFetchResult(pullRequests: [
            makeStackedPR(1, position: 1, status: .success),
            makeStackedPR(2, position: 2, status: .success),
        ], isPartial: false)
        await vm.refresh()
        #expect(spy.notifications.count == 1, "A partial fetch must not shrink the ready set and re-notify")
    }
}

@MainActor
@Suite(.serialized)
struct StackCompletionTests {

    private func stackedPR(_ number: Int, position: Int, size: Int, type: PRType) -> PullRequest {
        PullRequest(
            number: number,
            title: "PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: "widget", nameWithOwner: "acme/widget"),
            url: "https://github.com/acme/widget/pull/\(number)",
            author: PullRequest.Author(login: "alice"),
            headRefName: "feature/\(number)",
            updatedAt: Date(),
            buildStatus: .success,
            isWatched: false,
            labels: [],
            type: type,
            isDraft: false,
            statusChecks: [],
            reviewDecision: nil,
            host: "github.com",
            stack: PRStackInfo(id: "ST_stack", number: 9, size: size, position: position)
        )
    }

    private func makeVM(
        stub: StubGitHubService,
        stackResolutionTTL: TimeInterval = Constants.stackResolutionRevalidationInterval
    ) async -> PRMonitorViewModel {
        let vm = withDependencies {
            $0.userDefaults = UserDefaultsStore.testSuite()
            $0.watchlistService = WatchlistService()
            $0.notificationService = NoopNotificationService()
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = stub
        } operation: {
            PRMonitorViewModel(isDemoMode: false, stackResolutionTTL: stackResolutionTTL)
        }
        vm.stopPolling()
        // Let the poll started by init finish before the explicit refresh.
        await waitForInitialRefresh(vm)
        return vm
    }

    @Test
    func fillsInTheRestOfTheStackFromASingleAssignedPart() async {
        let stub = StubGitHubService()
        stub.result = PRFetchResult(
            pullRequests: [stackedPR(3, position: 3, size: 4, type: .reviewing)],
            isPartial: false
        )
        stub.stackParts = [
            stackedPR(1, position: 1, size: 4, type: .reviewing),
            stackedPR(2, position: 2, size: 4, type: .reviewing),
            stackedPR(4, position: 4, size: 4, type: .reviewing),
        ]

        let vm = await makeVM(stub: stub)

        await vm.refresh()

        #expect(vm.reviewPRs.map(\.number) == [1, 2, 3, 4])
        #expect(vm.authoredPRs.isEmpty)

        let rows = vm.sectionRows(for: .reviewing)
        #expect(rows.count == 5)
        guard case .stackHeader(let header) = rows.first else {
            Issue.record("Expected a single stack block")
            return
        }
        #expect(header.visibleParts.map(\.number) == [1, 2, 3, 4])
        #expect(header.summary == "All 4 parts are ready to merge")
    }

    @Test
    func passesTheAnchorsStackIdentityToTheCompletionLookup() async throws {
        let stub = StubGitHubService()
        stub.result = PRFetchResult(
            pullRequests: [stackedPR(3, position: 3, size: 4, type: .reviewing)],
            isPartial: false
        )
        stub.stackParts = [
            stackedPR(1, position: 1, size: 4, type: .reviewing),
            stackedPR(2, position: 2, size: 4, type: .reviewing),
            stackedPR(4, position: 4, size: 4, type: .reviewing),
        ]

        let vm = await makeVM(stub: stub)
        await vm.refresh()

        #expect(stub.fetchMissingStackPartsCalls.count == 1)
        let call = try #require(stub.fetchMissingStackPartsCalls.first)
        #expect(call.stackID == "ST_stack")
        #expect(call.host == "github.com")
        #expect(call.owner == "acme")
        #expect(call.repo == "widget")
        #expect(call.type == .reviewing)
    }

    @Test
    func marksFetchedCompanionsWithoutMarkingSearchedParts() async throws {
        let stub = StubGitHubService()
        stub.result = PRFetchResult(
            pullRequests: [stackedPR(3, position: 3, size: 4, type: .reviewing)],
            isPartial: false
        )
        stub.stackParts = [
            stackedPR(1, position: 1, size: 4, type: .reviewing),
            stackedPR(2, position: 2, size: 4, type: .reviewing),
            stackedPR(4, position: 4, size: 4, type: .reviewing),
        ]

        let vm = await makeVM(stub: stub)
        await vm.refresh()

        for number in [1, 2, 4] {
            let companion = try #require(vm.reviewPRs.first { $0.number == number })
            #expect(vm.isStackCompanion(companion), "fetched part #\(number) is a companion")
        }
        // The part that came from the user's own searches is not a companion.
        let anchor = try #require(vm.reviewPRs.first { $0.number == 3 })
        #expect(!vm.isStackCompanion(anchor))
    }

    @Test
    func leavesAStackAloneWhenItsPartsAreAllPresent() async {
        let stub = StubGitHubService()
        stub.result = PRFetchResult(
            pullRequests: [
                stackedPR(1, position: 1, size: 2, type: .reviewing),
                stackedPR(2, position: 2, size: 2, type: .reviewing),
            ],
            isPartial: false
        )
        stub.stackParts = [stackedPR(99, position: 1, size: 2, type: .reviewing)]

        let vm = await makeVM(stub: stub)

        await vm.refresh()

        #expect(vm.reviewPRs.map(\.number) == [1, 2])
    }

    @Test
    func accountsForMergedLowerPartsInTheHeader() async {
        let stub = StubGitHubService()
        stub.result = PRFetchResult(
            pullRequests: [
                stackedPR(2, position: 2, size: 3, type: .reviewing),
                stackedPR(3, position: 3, size: 3, type: .reviewing),
            ],
            isPartial: false
        )
        stub.stackMergedPositions = [1]

        let vm = await makeVM(stub: stub)

        await vm.refresh()

        #expect(vm.reviewPRs.map(\.number) == [2, 3])

        let rows = vm.sectionRows(for: .reviewing)
        guard case .stackHeader(let header) = rows.first else {
            Issue.record("Expected a stack header")
            return
        }
        #expect(header.readiness.landedPositions == [1])
        #expect(header.summary == "Part 1 merged · All remaining parts are ready to merge")
    }

    // MARK: - Stack resolution cache

    @Test
    func reusesAResolutionWhileTheVisiblePartsAreUnchangedAndRevalidatesWhenTheyChange() async {
        let stub = StubGitHubService()
        stub.result = PRFetchResult(
            pullRequests: [stackedPR(3, position: 3, size: 4, type: .reviewing)],
            isPartial: false
        )
        stub.stackParts = [
            stackedPR(1, position: 1, size: 4, type: .reviewing),
            stackedPR(2, position: 2, size: 4, type: .reviewing),
            stackedPR(4, position: 4, size: 4, type: .reviewing),
        ]

        // The initial refresh resolves the stack once.
        let vm = await makeVM(stub: stub)
        #expect(stub.fetchMissingStackPartsCallCount == 1)

        // The next poll sees the same visible part, so the cached resolution is
        // reused instead of refetching.
        await vm.refresh()
        #expect(stub.fetchMissingStackPartsCallCount == 1)
        #expect(vm.reviewPRs.map(\.number) == [1, 2, 3, 4])

        // A part appearing in the searches changes the visible set and must
        // trigger a fresh lookup even inside the interval.
        stub.result = PRFetchResult(
            pullRequests: [
                stackedPR(2, position: 2, size: 4, type: .reviewing),
                stackedPR(3, position: 3, size: 4, type: .reviewing),
            ],
            isPartial: false
        )
        await vm.refresh()
        #expect(stub.fetchMissingStackPartsCallCount == 2)
        #expect(vm.reviewPRs.map(\.number) == [1, 2, 3, 4])
    }

    @Test
    func revalidatesACachedStackOnceTheIntervalElapses() async {
        let stub = StubGitHubService()
        stub.result = PRFetchResult(
            pullRequests: [stackedPR(3, position: 3, size: 4, type: .reviewing)],
            isPartial: false
        )
        stub.stackParts = [
            stackedPR(1, position: 1, size: 4, type: .reviewing),
            stackedPR(2, position: 2, size: 4, type: .reviewing),
            stackedPR(4, position: 4, size: 4, type: .reviewing),
        ]

        // A zero interval expires the cached resolution immediately, so the
        // second refresh resolves again even though nothing visible changed.
        let vm = await makeVM(stub: stub, stackResolutionTTL: 0)
        #expect(stub.fetchMissingStackPartsCallCount == 1)

        await vm.refresh()
        #expect(stub.fetchMissingStackPartsCallCount == 2)
        #expect(vm.reviewPRs.map(\.number) == [1, 2, 3, 4])
    }

    @Test
    func transientRevalidationFailureKeepsWatchedCompanionsDisplayedAndWatched() async throws {
        let stub = StubGitHubService()
        stub.result = PRFetchResult(
            pullRequests: [stackedPR(3, position: 3, size: 4, type: .reviewing)],
            isPartial: false
        )
        stub.stackParts = [
            stackedPR(1, position: 1, size: 4, type: .reviewing),
            stackedPR(2, position: 2, size: 4, type: .reviewing),
            stackedPR(4, position: 4, size: 4, type: .reviewing),
        ]

        // A zero interval makes every refresh revalidate, so the failure below
        // hits the revalidation path right after the successful cached resolution.
        let vm = await makeVM(stub: stub, stackResolutionTTL: 0)
        #expect(stub.fetchMissingStackPartsCallCount == 1)
        #expect(vm.reviewPRs.map(\.number) == [1, 2, 3, 4])

        guard let anchor = vm.reviewPRs.first(where: { $0.number == 3 }) else {
            Issue.record("Expected the searched part to be displayed")
            return
        }
        vm.toggleWatch(for: anchor)
        #expect(vm.reviewPRs.allSatisfy { $0.isWatched })

        // The revalidation lookup fails transiently; nothing may prune the
        // companions or their watch state.
        stub.stackPartsError = TransientStackLookupError()
        await vm.refresh()

        // The call count proves the revalidation lookup ran and failed rather
        // than serving the cached resolution.
        #expect(stub.fetchMissingStackPartsCallCount == 2)
        #expect(vm.reviewPRs.map(\.number) == [1, 2, 3, 4], "watched companions must not be pruned when the revalidation lookup fails")
        #expect(vm.reviewPRs.allSatisfy { $0.isWatched }, "watched companions must remain watched")
        for number in [1, 2, 4] {
            let companion = try #require(vm.reviewPRs.first { $0.number == number })
            #expect(vm.isStackCompanion(companion), "retained companion #\(number) must remain marked as a companion")
        }

        // The lookup recovers; the companions come back and stay watched.
        stub.stackPartsError = nil
        await vm.refresh()
        // The count proves the lookup was retried after the failure instead of
        // caching it.
        #expect(stub.fetchMissingStackPartsCallCount == 3)
        #expect(vm.reviewPRs.map(\.number) == [1, 2, 3, 4])
        #expect(vm.reviewPRs.allSatisfy { $0.isWatched }, "watch state must survive the transient failure")
        // Every companion is restored with its companion marking, and the
        // searched part is never a companion.
        for number in [1, 2, 4] {
            let restored = try #require(vm.reviewPRs.first { $0.number == number })
            #expect(vm.isStackCompanion(restored), "restored companion #\(number) must be marked as a companion")
        }
        let recoveredAnchor = try #require(vm.reviewPRs.first { $0.number == 3 })
        #expect(!vm.isStackCompanion(recoveredAnchor), "the searched part must never be marked as a companion")
    }
}

@MainActor
@Suite(.serialized)
struct StackPartRemovalTests {

    private func pinnedPart(
        _ number: Int,
        position: Int,
        nameWithOwner: String = "acme/widget"
    ) -> PullRequest {
        PullRequest(
            number: number,
            title: "PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: "widget", nameWithOwner: nameWithOwner),
            url: "https://github.com/\(nameWithOwner)/pull/\(number)",
            author: PullRequest.Author(login: "alice"),
            headRefName: "feature/\(number)",
            updatedAt: Date(),
            buildStatus: .success,
            isWatched: false,
            labels: [],
            type: .other,
            isDraft: false,
            statusChecks: [],
            reviewDecision: nil,
            host: "github.com",
            stack: PRStackInfo(id: "ST_remove", number: 7, size: 2, position: position)
        )
    }

    private func makeVM(defaults: UserDefaultsStore, stub: StubGitHubService) async -> PRMonitorViewModel {
        let vm = withDependencies {
            $0.userDefaults = defaults
            $0.watchlistService = WatchlistService()
            $0.notificationService = NoopNotificationService()
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = stub
        } operation: {
            PRMonitorViewModel(isDemoMode: false)
        }
        vm.stopPolling()
        // Let the poll started by init finish before the explicit refreshes.
        await waitForInitialRefresh(vm)
        return vm
    }

    @Test
    func removedStackPartIsNotReAddedAndReAddingClearsTheExclusion() async throws {
        let defaults = UserDefaultsStore.testSuite()
        let stub = StubGitHubService()
        let part1 = pinnedPart(101, position: 1)
        let part2 = pinnedPart(102, position: 2)
        stub.otherPRResults = [part1]
        stub.stackParts = [part2]

        let vm = await makeVM(defaults: defaults, stub: stub)

        // Pin part 1 only; completion adds its sibling part 2 as a companion.
        try await vm.addOtherPR(urlString: "https://github.com/acme/widget/pull/101")
        await vm.refresh()
        #expect(vm.filteredOtherPRs.map(\.number) == [101, 102])

        // Removing the companion must stick across refreshes while the pinned
        // sibling keeps the stack alive.
        vm.removeOtherPR(part2)
        await vm.refresh()
        #expect(vm.filteredOtherPRs.map(\.number) == [101], "A removed stack part must not be re-added while a sibling anchor remains")

        // Re-adding the part clears the exclusion. Make its own fetch go stale
        // so only completion can bring it back, proving the exclusion is gone.
        stub.otherPRResults = [part1, part2]
        try await vm.addOtherPR(urlString: "https://github.com/acme/widget/pull/102")
        stub.otherPRResults = [part1]
        await vm.refresh()
        #expect(vm.filteredOtherPRs.map(\.number) == [101, 102], "Re-adding a part must clear the exclusion so completion is not permanently blocked")
    }

    @Test
    func removedStackPartStaysExcludedAfterRelaunchUntilExplicitlyReAdded() async throws {
        let defaults = UserDefaultsStore.testSuite()
        let stub = StubGitHubService()
        let anchor = pinnedPart(101, position: 1)
        let companion = pinnedPart(102, position: 2)
        stub.otherPRResults = [anchor]
        stub.stackParts = [companion]

        let firstVM = await makeVM(defaults: defaults, stub: stub)
        try await firstVM.addOtherPR(urlString: anchor.url)
        await firstVM.refresh()
        #expect(firstVM.filteredOtherPRs.map(\.number) == [101, 102])

        firstVM.removeOtherPR(companion)
        // The cached list still contains the part from before removal. A new VM
        // must filter it on restoration and on its first completion lookup.
        let secondVM = await makeVM(defaults: defaults, stub: stub)
        #expect(secondVM.filteredOtherPRs.map(\.number) == [101])
        await secondVM.refresh()
        #expect(secondVM.filteredOtherPRs.map(\.number) == [101], "completion must respect an exclusion loaded from defaults")

        stub.otherPRResults = [anchor, companion]
        try await secondVM.addOtherPR(urlString: companion.url)
        let storedData = try #require(defaults.data(forKey: .removedStackPartIDs))
        let storedIDs = try JSONDecoder().decode([String].self, from: storedData)
        #expect(!storedIDs.contains(companion.id.lowercased()), "explicit re-add must clear the persisted exclusion")
    }

    @Test
    func removalExclusionMatchesACompanionRebuiltUnderADifferentRepoCasing() async throws {
        let defaults = UserDefaultsStore.testSuite()
        let stub = StubGitHubService()
        // The anchor is pinned under the API-canonical casing; the other part comes
        // from a URL the user typed with different casing, so its id is
        // "Acme/Widget#102". Completion rebuilds companions with the anchor's
        // casing, producing "acme/widget#102" — the same part, different id case.
        let anchor = pinnedPart(101, position: 1)
        let pinnedWithTypedCasing = pinnedPart(102, position: 2, nameWithOwner: "Acme/Widget")
        let rebuiltCompanion = pinnedPart(102, position: 2)
        stub.otherPRResults = [anchor, pinnedWithTypedCasing]
        stub.stackParts = [rebuiltCompanion]

        let vm = await makeVM(defaults: defaults, stub: stub)

        // Pin both parts; the anchor keeps the stack alive after the other is removed.
        try await vm.addOtherPR(urlString: "https://github.com/acme/widget/pull/101")
        try await vm.addOtherPR(urlString: "https://github.com/Acme/Widget/pull/102")
        await vm.refresh()
        #expect(vm.filteredOtherPRs.map(\.number) == [101, 102])

        // Removing the typed-casing part must stick: the next completion rebuilds it
        // as "acme/widget#102", and the lowercased exclusion must still match.
        vm.removeOtherPR(pinnedWithTypedCasing)
        await vm.refresh()
        #expect(vm.filteredOtherPRs.map(\.number) == [101], "A removed stack part must stay removed even when completion rebuilds it under the anchor's casing")

        // Re-adding clears the exclusion. Make its own fetch go stale so only
        // completion can bring it back, proving the exclusion is gone.
        stub.otherPRResults = [anchor, pinnedWithTypedCasing]
        try await vm.addOtherPR(urlString: "https://github.com/Acme/Widget/pull/102")
        stub.otherPRResults = [anchor]
        await vm.refresh()
        #expect(vm.filteredOtherPRs.map(\.number) == [101, 102], "Re-adding a part must clear the exclusion regardless of its id casing")
    }

    @Test
    func isPinnedPRClassifiesPinnedCompanionAndAuthoredPRs() async throws {
        let defaults = UserDefaultsStore.testSuite()
        let stub = StubGitHubService()
        let pinned = pinnedPart(101, position: 1)
        stub.result = PRFetchResult(pullRequests: [], isPartial: false)
        stub.otherPRResults = [pinned]

        let vm = await makeVM(defaults: defaults, stub: stub)
        try await vm.addOtherPR(urlString: "https://github.com/acme/widget/pull/101")

        #expect(vm.isPinnedPR(pinned), "the part the user pinned is pinned")
        #expect(!vm.isPinnedPR(pinnedPart(102, position: 2)), "a companion part is not pinned")
        #expect(!vm.isPinnedPR(unstackedAuthoredPR()), "an authored PR is never pinned")
    }

    @Test
    func pinnedPartsAreNotCompanions() async throws {
        let defaults = UserDefaultsStore.testSuite()
        let stub = StubGitHubService()
        let anchor = pinnedPart(101, position: 1)
        let companion = pinnedPart(102, position: 2)
        stub.result = PRFetchResult(pullRequests: [], isPartial: false)
        stub.otherPRResults = [anchor]
        stub.stackParts = [companion]

        let vm = await makeVM(defaults: defaults, stub: stub)
        try await vm.addOtherPR(urlString: "https://github.com/acme/widget/pull/101")
        await vm.refresh()

        #expect(vm.filteredOtherPRs.map(\.number) == [101, 102])
        #expect(vm.isPinnedPR(anchor))
        #expect(!vm.isStackCompanion(anchor), "a part the user pinned is theirs, not a companion")
        #expect(vm.isStackCompanion(companion))
    }

    private func unstackedAuthoredPR() -> PullRequest {
        PullRequest(
            number: 55,
            title: "My own PR",
            repository: PullRequest.RepositoryInfo(name: "widget", nameWithOwner: "acme/widget"),
            url: "https://github.com/acme/widget/pull/55",
            author: PullRequest.Author(login: "alice"),
            headRefName: "feature/55",
            updatedAt: Date(),
            buildStatus: .success,
            isWatched: false,
            labels: [],
            type: .authored,
            isDraft: false,
            statusChecks: [],
            reviewDecision: nil,
            host: "github.com"
        )
    }

    private func stackPart(
        _ number: Int,
        position: Int,
        size: Int,
        type: PRType
    ) -> PullRequest {
        PullRequest(
            number: number,
            title: "PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: "widget", nameWithOwner: "acme/widget"),
            url: "https://github.com/acme/widget/pull/\(number)",
            author: PullRequest.Author(login: "alice"),
            headRefName: "feature/\(number)",
            updatedAt: Date(),
            buildStatus: .success,
            isWatched: false,
            labels: [],
            type: type,
            isDraft: false,
            statusChecks: [],
            reviewDecision: nil,
            host: "github.com",
            stack: PRStackInfo(id: "ST_promote", number: 11, size: size, position: position)
        )
    }

    // MARK: - Pinning a displayed companion by URL

    @Test
    func addingAURLForADisplayedOtherCompanionPinsItWithoutDuplicating() async throws {
        let defaults = UserDefaultsStore.testSuite()
        let stub = StubGitHubService()
        let anchor = pinnedPart(101, position: 1)
        let companion = pinnedPart(102, position: 2)
        stub.otherPRResults = [anchor]
        stub.stackParts = [companion]

        let vm = await makeVM(defaults: defaults, stub: stub)
        try await vm.addOtherPR(urlString: "https://github.com/acme/widget/pull/101")
        await vm.refresh()
        #expect(vm.filteredOtherPRs.map(\.number) == [101, 102])
        #expect(vm.isStackCompanion(companion), "precondition: #102 is displayed as a companion")

        // Pinning the displayed companion by URL must leave exactly one occurrence.
        stub.otherPRResults = [anchor, companion]
        try await vm.addOtherPR(urlString: "https://github.com/acme/widget/pull/102")

        #expect(vm.filteredOtherPRs.filter { $0.number == 102 }.count == 1, "a pinned companion must appear exactly once")
        let pinned = try #require(vm.filteredOtherPRs.first { $0.number == 102 })
        #expect(vm.isPinnedPR(pinned))
        #expect(!vm.isStackCompanion(pinned), "a part the user pinned is no longer a companion")

        // The next refresh keeps the pinned part exactly once.
        await vm.refresh()
        #expect(vm.filteredOtherPRs.filter { $0.number == 102 }.count == 1)
    }

    @Test
    func addingAURLForADisplayedMainListCompanionPromotesItToPinnedOther() async throws {
        let defaults = UserDefaultsStore.testSuite()
        let stub = StubGitHubService()
        stub.result = PRFetchResult(
            pullRequests: [stackPart(3, position: 3, size: 4, type: .reviewing)],
            isPartial: false
        )
        stub.stackParts = [
            stackPart(1, position: 1, size: 4, type: .reviewing),
            stackPart(2, position: 2, size: 4, type: .reviewing),
            stackPart(4, position: 4, size: 4, type: .reviewing),
        ]

        let vm = await makeVM(defaults: defaults, stub: stub)
        await vm.refresh()
        #expect(vm.reviewPRs.map(\.number) == [1, 2, 3, 4])
        let companion = try #require(vm.reviewPRs.first { $0.number == 1 })
        #expect(vm.isStackCompanion(companion), "precondition: #1 is a displayed main-list companion")

        // Adding its URL must pin it in Other instead of rejecting it as
        // already tracked. The stubbed fetch mirrors the real service, which
        // builds Other PRs with type .other.
        stub.otherPRResults = [stackPart(1, position: 1, size: 4, type: .other)]
        try await vm.addOtherPR(urlString: "https://github.com/acme/widget/pull/1")

        // The add itself promotes the companion: it renders as a pinned .other
        // row and is gone from the main list.
        let promoted = try #require(vm.filteredOtherPRs.first { $0.number == 1 })
        #expect(promoted.type == .other)
        #expect(vm.isPinnedPR(promoted))
        #expect(!vm.reviewPRs.contains { $0.number == 1 })

        // The accepted section behavior extends across .other too: with part 1
        // pinned there and parts 2-4 searched as Reviewing, the stack renders
        // once, as a single complete block under the lowest member's category
        // (Other), and Reviewing shows no duplicate stack block.
        await vm.refresh()
        let otherRows = vm.sectionRows(for: .other)
        #expect(otherRows.count == 5, "the complete stack renders as one block under Other")
        guard case .stackHeader(let otherHeader) = otherRows.first else {
            Issue.record("Expected a single stack header in the Other section")
            return
        }
        #expect(otherHeader.visibleParts.map(\.number) == [1, 2, 3, 4])
        #expect(otherRows.compactMap(\.pr).map(\.number) == [1, 2, 3, 4])
        #expect(vm.sectionRows(for: .reviewing).isEmpty, "Reviewing must not repeat the stack block")

        // Part 1 is the pinned one; the completion-fetched parts are not.
        let pinnedRow = try #require(otherRows.compactMap(\.pr).first { $0.number == 1 })
        #expect(vm.isPinnedPR(pinnedRow), "the promoted part must remain pinned after the refresh")
        for number in [2, 3, 4] {
            let part = try #require(otherRows.compactMap(\.pr).first { $0.number == number })
            #expect(!vm.isPinnedPR(part), "fetched part #\(number) must not read as pinned")
        }
    }

    @Test
    func addingAURLForATrackedNonCompanionPRIsStillRejected() async throws {
        let defaults = UserDefaultsStore.testSuite()
        let stub = StubGitHubService()
        // The whole stack is visible in the main list, so none of its parts are
        // companions: they all matched the user's own searches.
        stub.result = PRFetchResult(
            pullRequests: [
                stackPart(1, position: 1, size: 2, type: .authored),
                stackPart(2, position: 2, size: 2, type: .authored),
            ],
            isPartial: false
        )

        let vm = await makeVM(defaults: defaults, stub: stub)
        await vm.refresh()
        #expect(vm.authoredPRs.map(\.number) == [1, 2])

        do {
            try await vm.addOtherPR(urlString: "https://github.com/acme/widget/pull/2")
            Issue.record("Expected OtherPRError.alreadyTracked to be thrown")
        } catch let error as OtherPRError {
            #expect(error == .alreadyTracked)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

@MainActor
@Suite(.serialized)
struct StackSpanningSectionsTests {

    private func stackedPart(
        _ number: Int,
        position: Int,
        type: PRType,
        nameWithOwner: String = "acme/widget"
    ) -> PullRequest {
        PullRequest(
            number: number,
            title: "PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: "widget", nameWithOwner: nameWithOwner),
            url: "https://github.com/\(nameWithOwner)/pull/\(number)",
            author: PullRequest.Author(login: "alice"),
            headRefName: "feature/\(number)",
            updatedAt: Date(),
            buildStatus: .success,
            isWatched: false,
            labels: [],
            type: type,
            isDraft: false,
            statusChecks: [],
            reviewDecision: nil,
            host: "github.com",
            stack: PRStackInfo(id: "ST_span", number: 5, size: 2, position: position)
        )
    }

    private func makeVM(stub: StubGitHubService) async -> PRMonitorViewModel {
        let vm = withDependencies {
            $0.userDefaults = UserDefaultsStore.testSuite()
            $0.watchlistService = WatchlistService()
            $0.notificationService = NoopNotificationService()
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = stub
        } operation: {
            let vm = PRMonitorViewModel(isDemoMode: false)
            vm.stopPolling()
            return vm
        }
        // Let the poll started by init finish before the explicit refresh.
        await waitForInitialRefresh(vm)
        return vm
    }

    @Test
    func aStackSpanningAuthoredAndReviewingRendersOneBlockInTheLowestMembersCategory() async {
        let stub = StubGitHubService()
        // GitHub's searches can return one part of a stack as the user's own PR
        // and another as one awaiting their review. The fetched order below also
        // encounters the higher-position reviewing part before the lower
        // authored part, so the rendering cannot depend on fetch order.
        stub.result = PRFetchResult(pullRequests: [
            stackedPart(2, position: 2, type: .reviewing),
            stackedPart(1, position: 1, type: .authored),
        ], isPartial: false)

        let vm = await makeVM(stub: stub)
        await vm.refresh()

        let authoredRows = vm.sectionRows(for: .authored)
        #expect(authoredRows.count == 3, "the whole stack renders as one block in the lowest member's category")
        guard case .stackHeader(let header) = authoredRows.first else {
            Issue.record("Expected a single stack header in the authored section")
            return
        }
        #expect(header.visibleParts.map(\.number) == [1, 2])
        #expect(authoredRows.compactMap(\.pr).map(\.number) == [1, 2])

        #expect(vm.sectionRows(for: .reviewing).isEmpty, "no partial second block in the reviewing category")
    }

    @Test
    func higherPinnedOtherPartJoinsTheLowerReviewingPart() async throws {
        let stub = StubGitHubService()
        stub.result = PRFetchResult(pullRequests: [
            stackedPart(1, position: 1, type: .reviewing),
        ], isPartial: false)
        stub.otherPRResults = [stackedPart(2, position: 2, type: .other)]

        let vm = await makeVM(stub: stub)
        try await vm.addOtherPR(urlString: "https://github.com/acme/widget/pull/2")
        await vm.refresh()

        let reviewingRows = vm.sectionRows(for: .reviewing)
        #expect(reviewingRows.count == 3)
        #expect(reviewingRows.compactMap(\.pr).map(\.number) == [1, 2])
        #expect(vm.sectionRows(for: .other).isEmpty, "a higher pinned part must not create another stack block")
    }

    @Test
    func selectedRepositoryGroupsDifferentlyCasedMembersWithoutDuplicatePickerEntries() async throws {
        let stub = StubGitHubService()
        stub.result = PRFetchResult(pullRequests: [
            stackedPart(2, position: 2, type: .reviewing),
        ], isPartial: false)
        stub.otherPRResults = [stackedPart(1, position: 1, type: .other, nameWithOwner: "Acme/Widget")]

        let vm = await makeVM(stub: stub)
        try await vm.addOtherPR(urlString: "https://github.com/Acme/Widget/pull/1")
        await vm.refresh()
        #expect(vm.availableRepositories == ["acme/widget"], "the picker should show one readable repository name")

        vm.selectedRepository = "Acme/Widget"
        #expect(vm.availableRepositories.contains(vm.selectedRepository), "a persisted selection must match a picker entry")
        let otherRows = vm.sectionRows(for: .other)
        #expect(otherRows.count == 3)
        guard case .stackHeader(let header) = otherRows.first else {
            Issue.record("Expected one complete stack block under Other")
            return
        }
        #expect(header.visibleParts.map(\.number) == [1, 2])
        #expect(vm.sectionRows(for: .reviewing).isEmpty)

        await vm.refresh()
        #expect(vm.selectedRepository.lowercased() == "acme/widget", "refresh must not reset an equivalent repository selection")
        #expect(vm.sectionRows(for: .other).count == 3)
    }
}

@MainActor
@Suite(.serialized)
struct StackColdStartFailureTests {

    private func coldPart(
        _ number: Int,
        position: Int,
        size: Int,
        type: PRType
    ) -> PullRequest {
        PullRequest(
            number: number,
            title: "PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: "widget", nameWithOwner: "acme/widget"),
            url: "https://github.com/acme/widget/pull/\(number)",
            author: PullRequest.Author(login: "alice"),
            headRefName: "feature/\(number)",
            updatedAt: Date(),
            buildStatus: .success,
            isWatched: false,
            labels: [],
            type: type,
            isDraft: false,
            statusChecks: [],
            reviewDecision: nil,
            host: "github.com",
            stack: PRStackInfo(id: "ST_cold", number: 13, size: size, position: position)
        )
    }

    /// Seeds the persisted state a previous session left behind: the PR cache
    /// holds the fully resolved stack and its parts are watched.
    private func seedPersistedState(defaults: UserDefaultsStore, prs: [PullRequest]) {
        let cache = withDependencies {
            $0.userDefaults = defaults
        } operation: {
            PRCacheService()
        }
        cache.save(mainPRs: prs, otherPRs: [])

        let watchlist = withDependencies {
            $0.userDefaults = defaults
        } operation: {
            WatchlistService()
        }
        for pr in prs {
            watchlist.watch(pr)
        }
    }

    @Test
    func coldStartWithFailingLookupKeepsCachedWatchedCompanions() async throws {
        let defaults = UserDefaultsStore.testSuite()
        seedPersistedState(
            defaults: defaults,
            prs: [
                coldPart(1, position: 1, size: 4, type: .reviewing),
                coldPart(2, position: 2, size: 4, type: .reviewing),
                coldPart(3, position: 3, size: 4, type: .reviewing),
                coldPart(4, position: 4, size: 4, type: .reviewing),
            ]
        )

        // Relaunch: a fresh VM restores the cached lists (its in-memory stack
        // resolution cache starts empty) and its first completion lookup is
        // held in flight at a deterministic gate.
        let stub = StubGitHubService()
        stub.result = PRFetchResult(
            pullRequests: [coldPart(3, position: 3, size: 4, type: .reviewing)],
            isPartial: false
        )
        stub.stackParts = [
            coldPart(1, position: 1, size: 4, type: .reviewing),
            coldPart(2, position: 2, size: 4, type: .reviewing),
            coldPart(4, position: 4, size: 4, type: .reviewing),
        ]
        let gate = StackLookupGate()
        stub.lookupGate = gate
        // Arm the fallback release before anything can suspend on the gate, so
        // a polling timeout or early return also releases a subsequently held
        // lookup instead of leaving the init refresh hanging. It is idempotent
        // with the explicit release at the intended failure point below.
        defer { gate.release(throwing: TransientStackLookupError()) }

        let spy = StackReadySpy()
        let vm = withDependencies {
            $0.userDefaults = defaults
            $0.watchlistService = WatchlistService()
            $0.notificationService = spy
            $0.otherPRsService = OtherPRsService()
            $0.customNamesService = CustomNamesService()
            $0.cacheService = PRCacheService()
            $0[GitHubServiceKey.self] = stub
        } operation: {
            PRMonitorViewModel(isDemoMode: false, stackResolutionTTL: 0)
        }
        vm.stopPolling()

        // Wait until the init refresh's completion lookup is in flight, then
        // act on the VM while it is held there: condition-based, with an
        // explicit failure instead of relying on scheduling.
        for _ in 0..<200 {
            if stub.fetchMissingStackPartsCallCount == 1 { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard stub.fetchMissingStackPartsCallCount == 1 else {
            Issue.record("The init refresh's completion lookup never started")
            return
        }
        #expect(vm.lastRefreshTime == nil, "the init refresh must still be in flight")

        // While the lookup is held, the cached main-list companion remains
        // promotable by URL.
        stub.otherPRResults = [coldPart(1, position: 1, size: 4, type: .other)]
        try await vm.addOtherPR(urlString: "https://github.com/acme/widget/pull/1")
        let promoted = try #require(vm.filteredOtherPRs.first { $0.number == 1 })
        #expect(vm.isPinnedPR(promoted), "the cached companion is promotable while the first lookup is still in flight")
        #expect(promoted.isWatched, "the pinned part remains watched")
        #expect(!vm.reviewPRs.contains { $0.number == 1 })

        // The accepted layout holds while the lookup is still in flight: one
        // complete block under Other, no duplicate in Reviewing.
        let suspendedOtherRows = vm.sectionRows(for: .other)
        #expect(suspendedOtherRows.count == 5, "the complete stack renders as one block under Other while the lookup is in flight")
        guard case .stackHeader(let suspendedHeader) = suspendedOtherRows.first else {
            Issue.record("Expected a stack header in the Other section while the lookup is in flight")
            return
        }
        #expect(suspendedHeader.visibleParts.map(\.number) == [1, 2, 3, 4])
        #expect(vm.sectionRows(for: .reviewing).isEmpty, "Reviewing must not repeat the stack block")

        // Release the held lookup with a transient failure; the init refresh
        // then completes without retrying the lookup within itself.
        gate.release(throwing: TransientStackLookupError())
        await waitForInitialRefresh(vm)
        #expect(stub.fetchMissingStackPartsCallCount == 1, "a failed lookup must not be retried within the same refresh")

        // The failed refresh must not lose the stack: exactly one complete
        // Other block, no Reviewing duplicate, everything still watched.
        let postFailureOtherRows = vm.sectionRows(for: .other)
        #expect(postFailureOtherRows.count == 5, "the failed refresh must leave one complete Other block")
        guard case .stackHeader(let postFailureHeader) = postFailureOtherRows.first else {
            Issue.record("Expected a stack header in the Other section after the failed refresh")
            return
        }
        #expect(postFailureHeader.visibleParts.map(\.number) == [1, 2, 3, 4])
        #expect(postFailureOtherRows.compactMap(\.pr).map(\.number) == [1, 2, 3, 4])
        #expect(vm.sectionRows(for: .reviewing).isEmpty, "Reviewing must not repeat the stack block")
        #expect(postFailureOtherRows.compactMap(\.pr).allSatisfy { $0.isWatched }, "all parts must remain watched after the failed refresh")
        #expect(spy.notifications.isEmpty, "cached green parts cannot trigger a ready notification after a failed lookup")

        // Resolution recovers: the next refresh retries the lookup, the layout
        // settles, and the promotion plus watch state survive.
        await vm.refresh()
        #expect(stub.fetchMissingStackPartsCallCount == 2, "the lookup must be retried after recovery")
        let recoveredOtherRows = vm.sectionRows(for: .other)
        #expect(recoveredOtherRows.count == 5, "the recovered stack renders as one complete Other block")
        guard case .stackHeader(let recoveredHeader) = recoveredOtherRows.first else {
            Issue.record("Expected a stack header in the Other section after recovery")
            return
        }
        #expect(recoveredHeader.visibleParts.map(\.number) == [1, 2, 3, 4])
        #expect(recoveredOtherRows.compactMap(\.pr).map(\.number) == [1, 2, 3, 4])
        #expect(vm.sectionRows(for: .reviewing).isEmpty, "Reviewing must not repeat the stack block")

        let recoveredDisplayed = recoveredOtherRows.compactMap(\.pr)
        #expect(recoveredDisplayed.allSatisfy { $0.isWatched }, "watch state must survive the failure and recovery")
        for number in [2, 4] {
            let companion = try #require(recoveredDisplayed.first { $0.number == number })
            #expect(vm.isStackCompanion(companion), "restored companion #\(number) must be marked as a companion")
        }
        let recoveredAnchor = try #require(recoveredDisplayed.first { $0.number == 3 })
        #expect(!vm.isStackCompanion(recoveredAnchor), "the searched part must never be marked as a companion")
        let promotedRow = try #require(recoveredDisplayed.first { $0.number == 1 })
        #expect(vm.isPinnedPR(promotedRow), "the promotion survives the recovery")
        #expect(!vm.isStackCompanion(promotedRow), "the pinned part is not a companion")
        #expect(spy.notifications.count == 1, "a successful retry can evaluate the watched stack")
    }
}
