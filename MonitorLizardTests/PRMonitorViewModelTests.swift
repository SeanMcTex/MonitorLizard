import Testing
import Foundation
@testable import MonitorLizard

struct ParsePRURLTests {

    @Test func validGitHubURL() {
        let id = GitHubService.parsePRURL("https://github.com/owner/repo/pull/123")
        #expect(id?.host == "github.com")
        #expect(id?.owner == "owner")
        #expect(id?.repo == "repo")
        #expect(id?.number == 123)
    }

    @Test func validGHEURL() {
        let id = GitHubService.parsePRURL("https://github.example.com/myorg/myrepo/pull/42")
        #expect(id?.host == "github.example.com")
        #expect(id?.owner == "myorg")
        #expect(id?.repo == "myrepo")
        #expect(id?.number == 42)
    }

    @Test func invalidURLNotPullPath() {
        let id = GitHubService.parsePRURL("https://github.com/owner/repo/issues/123")
        #expect(id == nil)
    }

    @Test func invalidURLMissingNumber() {
        let id = GitHubService.parsePRURL("https://github.com/owner/repo/pull/")
        #expect(id == nil)
    }

    @Test func invalidURLNonNumericNumber() {
        let id = GitHubService.parsePRURL("https://github.com/owner/repo/pull/abc")
        #expect(id == nil)
    }

    @Test func invalidURLNoHost() {
        let id = GitHubService.parsePRURL("not-a-url")
        #expect(id == nil)
    }

    @Test func invalidURLEmpty() {
        let id = GitHubService.parsePRURL("")
        #expect(id == nil)
    }

    @Test func validURLWithTrailingSlash() {
        // Extra path components — should not match
        let id = GitHubService.parsePRURL("https://github.com/owner/repo/pull/123/files")
        #expect(id == nil)
    }
}

struct OtherPRsServiceTests {

    private func makeService() -> OtherPRsService {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return OtherPRsService(defaults: suite)
    }

    private func makeID(number: Int = 1) -> OtherPRIdentifier {
        OtherPRIdentifier(host: "github.com", owner: "owner", repo: "repo", number: number)
    }

    @Test func startsEmpty() {
        let service = makeService()
        #expect(service.all().isEmpty)
    }

    @Test func addAndContains() {
        let service = makeService()
        let id = makeID()
        service.add(id)
        #expect(service.contains(id))
        #expect(service.all().count == 1)
    }

    @Test func addDuplicateIsIdempotent() {
        let service = makeService()
        let id = makeID()
        service.add(id)
        service.add(id)
        #expect(service.all().count == 1)
    }

    @Test func removeExisting() {
        let service = makeService()
        let id = makeID()
        service.add(id)
        service.remove(id)
        #expect(!service.contains(id))
        #expect(service.all().isEmpty)
    }

    @Test func removeNonExistentIsNoop() {
        let service = makeService()
        service.remove(makeID())
        #expect(service.all().isEmpty)
    }

    @Test func addMultiple() {
        let service = makeService()
        service.add(makeID(number: 1))
        service.add(makeID(number: 2))
        service.add(makeID(number: 3))
        #expect(service.all().count == 3)
    }

    @Test func clearAll() {
        let service = makeService()
        service.add(makeID(number: 1))
        service.add(makeID(number: 2))
        service.clearAll()
        #expect(service.all().isEmpty)
    }
}

struct CustomNamesServiceTests {

    private func makeService() -> CustomNamesService {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return CustomNamesService(defaults: suite)
    }

    @Test func startsEmpty() {
        let service = makeService()
        #expect(service.allNames().isEmpty)
    }

    @Test func setAndGet() {
        let service = makeService()
        service.setName("My PR", for: "owner/repo#1")
        #expect(service.name(for: "owner/repo#1") == "My PR")
    }

    @Test func removeRestoresNil() {
        let service = makeService()
        service.setName("My PR", for: "owner/repo#1")
        service.removeName(for: "owner/repo#1")
        #expect(service.name(for: "owner/repo#1") == nil)
    }

    @Test func pruneStaleRemovesInactiveEntries() {
        let service = makeService()
        service.setName("Active PR", for: "owner/repo#1")
        service.setName("Stale PR", for: "owner/repo#2")

        service.pruneStale(keeping: ["owner/repo#1"])

        #expect(service.name(for: "owner/repo#1") == "Active PR")
        #expect(service.name(for: "owner/repo#2") == nil)
    }

    @Test func pruneStaleKeepsAllWhenAllActive() {
        let service = makeService()
        service.setName("PR One", for: "owner/repo#1")
        service.setName("PR Two", for: "owner/repo#2")

        service.pruneStale(keeping: ["owner/repo#1", "owner/repo#2"])

        #expect(service.allNames().count == 2)
    }

    @Test func pruneStaleWithEmptySetClearsAll() {
        let service = makeService()
        service.setName("PR One", for: "owner/repo#1")

        service.pruneStale(keeping: [])

        #expect(service.allNames().isEmpty)
    }
}

@MainActor
struct OtherPRsViewModelTests {

    private func makeIsolatedServices() -> (WatchlistService, OtherPRsService) {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return (WatchlistService(defaults: suite), OtherPRsService(defaults: suite))
    }

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

    @Test func addOtherPRThrowsInvalidURL() async {
        let (watchlist, otherPRs) = makeIsolatedServices()
        let vm = PRMonitorViewModel(isDemoMode: true, watchlistService: watchlist, otherPRsService: otherPRs)
        vm.stopPolling()
        do {
            try await vm.addOtherPR(urlString: "not-a-valid-url")
            Issue.record("Expected OtherPRError.invalidURL to be thrown")
        } catch let error as OtherPRError {
            #expect(error == .invalidURL)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func addOtherPRThrowsAlreadyTrackedForAuthoredPR() async {
        let (watchlist, otherPRs) = makeIsolatedServices()
        let vm = PRMonitorViewModel(isDemoMode: true, watchlistService: watchlist, otherPRsService: otherPRs)
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

    @Test func addOtherPRAlreadyTrackedIsCaseInsensitive() async {
        let (watchlist, otherPRs) = makeIsolatedServices()
        let vm = PRMonitorViewModel(isDemoMode: true, watchlistService: watchlist, otherPRsService: otherPRs)
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

    @Test func filteredOtherPRsRespectSelectedRepository() {
        let (watchlist, otherPRs) = makeIsolatedServices()
        let vm = PRMonitorViewModel(isDemoMode: true, watchlistService: watchlist, otherPRsService: otherPRs)
        vm.stopPolling()
        defer { UserDefaults.standard.removeObject(forKey: "selectedRepository") }

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

    @Test func removeOtherPRResetsRepoSelectionWhenLastRemoved() {
        let (watchlist, otherPRs) = makeIsolatedServices()
        let vm = PRMonitorViewModel(isDemoMode: true, watchlistService: watchlist, otherPRsService: otherPRs)
        vm.stopPolling()
        defer { UserDefaults.standard.removeObject(forKey: "selectedRepository") }

        let pr = makePR(number: 99, nameWithOwner: "acme/widget")
        vm.otherPullRequests = [pr]
        vm.selectedRepository = "acme/widget"

        vm.removeOtherPR(pr)

        #expect(vm.selectedRepository == "All Repositories")
    }

    @Test func toggleWatchUpdatesOtherPullRequests() {
        let (watchlist, otherPRs) = makeIsolatedServices()
        let vm = PRMonitorViewModel(isDemoMode: true, watchlistService: watchlist, otherPRsService: otherPRs)
        vm.stopPolling()

        var pr = makePR(number: 1, nameWithOwner: "acme/widget")
        pr.isWatched = false
        vm.otherPullRequests = [pr]

        vm.toggleWatch(for: pr)
        #expect(vm.otherPullRequests[0].isWatched == true)

        vm.toggleWatch(for: vm.otherPullRequests[0])
        #expect(vm.otherPullRequests[0].isWatched == false)
    }

    @Test func clearAllWatchedResetsOtherPullRequests() {
        let (watchlist, otherPRs) = makeIsolatedServices()
        let vm = PRMonitorViewModel(isDemoMode: true, watchlistService: watchlist, otherPRsService: otherPRs)
        vm.stopPolling()

        var pr = makePR(number: 1, nameWithOwner: "acme/widget")
        pr.isWatched = true
        vm.otherPullRequests = [pr]

        vm.clearAllWatched()

        #expect(vm.otherPullRequests[0].isWatched == false)
    }

    @Test func removeOtherPRClearsCustomName() {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let customNames = CustomNamesService(defaults: suite)
        let (watchlist, otherPRs) = (WatchlistService(defaults: suite), OtherPRsService(defaults: suite))
        let vm = PRMonitorViewModel(
            isDemoMode: true,
            watchlistService: watchlist,
            otherPRsService: otherPRs,
            customNamesService: customNames
        )
        vm.stopPolling()

        let pr = makePR(number: 99, nameWithOwner: "acme/widget")
        vm.otherPullRequests = [pr]
        customNames.setName("Custom Name", for: pr.id)

        vm.removeOtherPR(pr)

        #expect(customNames.name(for: pr.id) == nil)
    }

    @Test func removeOtherPRKeepsRepoSelectionWhenOthersRemain() {
        let (watchlist, otherPRs) = makeIsolatedServices()
        let vm = PRMonitorViewModel(isDemoMode: true, watchlistService: watchlist, otherPRsService: otherPRs)
        vm.stopPolling()
        defer { UserDefaults.standard.removeObject(forKey: "selectedRepository") }

        let pr1 = makePR(number: 1, nameWithOwner: "acme/widget")
        let pr2 = makePR(number: 2, nameWithOwner: "acme/widget")
        vm.otherPullRequests = [pr1, pr2]
        vm.selectedRepository = "acme/widget"

        vm.removeOtherPR(pr1)

        #expect(vm.selectedRepository == "acme/widget")
    }
}

@MainActor
struct PRMonitorViewModelTests {

    private func makeIsolatedServices() -> (WatchlistService, OtherPRsService) {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return (WatchlistService(defaults: suite), OtherPRsService(defaults: suite))
    }

    private func createLoadedViewModel() async -> PRMonitorViewModel {
        let (watchlist, otherPRs) = makeIsolatedServices()
        let vm = PRMonitorViewModel(isDemoMode: true, watchlistService: watchlist, otherPRsService: otherPRs)
        // Poll until demo data is loaded rather than using a fixed sleep,
        // so the test doesn't flake under parallel load.
        for _ in 0..<40 {
            if !vm.authoredPRs.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return vm
    }

    @Test func availableRepositories() async {
        let vm = await createLoadedViewModel()

        let repos = vm.availableRepositories
        #expect(repos.count == 2)
        #expect(repos == ["feline-federation/cat-show-tracker", "fromagerie/cheese-cellar-manager"])
    }

    @Test func defaultSelectedRepository() async {
        let vm = await createLoadedViewModel()

        #expect(vm.selectedRepository == "All Repositories")
    }

    @Test func filterByRepository() async {
        let vm = await createLoadedViewModel()
        defer { UserDefaults.standard.removeObject(forKey: "selectedRepository") }

        vm.selectedRepository = "fromagerie/cheese-cellar-manager"

        // All authored PRs should be from cheese-cellar-manager
        #expect(!vm.authoredPRs.isEmpty)
        #expect(vm.authoredPRs.allSatisfy { $0.repository.nameWithOwner == "fromagerie/cheese-cellar-manager" })

        // No review PRs should appear (review PRs are all from cat-show-tracker)
        #expect(vm.reviewPRs.isEmpty)
    }

    @Test func filterByRepositoryShowsReviewPRs() async {
        let vm = await createLoadedViewModel()
        defer { UserDefaults.standard.removeObject(forKey: "selectedRepository") }

        vm.selectedRepository = "feline-federation/cat-show-tracker"

        // Review PRs should appear from cat-show-tracker
        #expect(!vm.reviewPRs.isEmpty)
        #expect(vm.reviewPRs.allSatisfy { $0.repository.nameWithOwner == "feline-federation/cat-show-tracker" })

        // No authored PRs should appear (authored PRs are all from cheese-cellar-manager)
        #expect(vm.authoredPRs.isEmpty)
    }

    @Test func allRepositoriesShowsEverything() async {
        let vm = await createLoadedViewModel()

        vm.selectedRepository = "All Repositories"

        let totalPRs = vm.authoredPRs.count + vm.reviewPRs.count
        // Demo data has 6 authored + 2 reviewing = 8 total
        #expect(totalPRs == 8)
    }

    @Test func selectedRepoResetOnRefresh() async {
        let vm = await createLoadedViewModel()

        // Set to a repo that exists
        vm.selectedRepository = "feline-federation/cat-show-tracker"
        #expect(vm.selectedRepository == "feline-federation/cat-show-tracker")

        // Now set to a repo that doesn't exist in the data
        vm.selectedRepository = "nonexistent/repo"

        // After refresh, it should reset to "All Repositories"
        await vm.refresh()
        #expect(vm.selectedRepository == "All Repositories")
    }

    @Test func renamePRUpdatesDisplayTitleInMemory() async {
        let vm = await createLoadedViewModel()

        guard let pr = vm.authoredPRs.first else {
            Issue.record("No authored PRs in demo data")
            return
        }

        vm.renamePR(pr, to: "My Custom Name")

        let updated = vm.authoredPRs.first { $0.id == pr.id }
        #expect(updated?.customName == "My Custom Name")
        #expect(updated?.displayTitle == "My Custom Name")
        #expect(updated?.title == pr.title) // GitHub title unchanged
    }

    @Test func renamePRNilRestoresGitHubTitle() async {
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

    @Test func renamePREmptyStringActsAsNil() async {
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

    @Test func sortPutsChangesRequestedFirst() async {
        // Demo PR #421 has buildStatus: .success and reviewDecision: .changesRequested
        // It should sort before pure-success PRs (e.g., no reviewDecision) when sorting is on.
        UserDefaults.standard.set(true, forKey: "sortNonSuccessFirst")
        defer { UserDefaults.standard.removeObject(forKey: "sortNonSuccessFirst") }

        let vm = await createLoadedViewModel()

        let authored = vm.authoredPRs
        // changesRequested PR (#421) should appear before any pure-success PR with no review issues
        let changesRequestedIndex = authored.firstIndex(where: { $0.reviewDecision == .changesRequested })
        let pureSuccessIndex = authored.firstIndex(where: { $0.buildStatus == .success && $0.reviewDecision == nil })

        if let crIdx = changesRequestedIndex, let psIdx = pureSuccessIndex {
            #expect(crIdx < psIdx)
        }
    }
}
