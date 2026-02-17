import Testing
@testable import MonitorLizard

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

        vm.selectedRepository = "fromagerie/cheese-cellar-manager"

        // All authored PRs should be from cheese-cellar-manager
        #expect(!vm.authoredPRs.isEmpty)
        #expect(vm.authoredPRs.allSatisfy { $0.repository.nameWithOwner == "fromagerie/cheese-cellar-manager" })

        // No review PRs should appear (review PRs are all from cat-show-tracker)
        #expect(vm.reviewPRs.isEmpty)
    }

    @Test func filterByRepositoryShowsReviewPRs() async {
        let vm = await createLoadedViewModel()

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
}
