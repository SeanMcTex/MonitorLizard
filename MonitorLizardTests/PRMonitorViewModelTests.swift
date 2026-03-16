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

@MainActor
struct PRMonitorViewModelTests {

    private func createLoadedViewModel() async -> PRMonitorViewModel {
        let vm = PRMonitorViewModel(isDemoMode: true)
        // Wait for the initial async refresh to complete
        // Demo mode refresh is fast, but we need to give it time
        try? await Task.sleep(for: .milliseconds(500))
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
