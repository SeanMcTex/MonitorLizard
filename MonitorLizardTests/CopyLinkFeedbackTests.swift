import Dependencies
import Testing
import Foundation
import AppKit
@testable import MonitorLizard

@MainActor
struct CopyPRLinkTests {

    private func makePR(url: String = "https://github.com/owner/repo/pull/1") -> PullRequest {
        PullRequest(
            number: 1,
            title: "Test PR",
            repository: PullRequest.RepositoryInfo(name: "repo", nameWithOwner: "owner/repo"),
            url: url,
            author: PullRequest.Author(login: "user"),
            headRefName: "feature",
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

    private func makeViewModel() -> PRMonitorViewModel {
        withDependencies {
            $0.userDefaults = UserDefaultsStore.testSuite()
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

    @Test func clipboardContainsPRURL() {
        let pr = makePR(url: "https://github.com/owner/repo/pull/42")
        let vm = makeViewModel()

        vm.copyPRLink(for: pr)

        let clipboard = NSPasteboard.general.string(forType: .string)
        #expect(clipboard == "https://github.com/owner/repo/pull/42")
    }

    @Test func copiedPRIDSetImmediately() {
        let pr = makePR()
        let vm = makeViewModel()

        vm.copyPRLink(for: pr)

        #expect(vm.copiedPRID == pr.id)
    }

    @Test func copiedPRIDNilBeforeCopy() {
        let vm = makeViewModel()
        #expect(vm.copiedPRID == nil)
    }

    @Test func copiedPRIDClearsAfterDelay() async {
        let pr = makePR()
        let vm = makeViewModel()

        vm.copyPRLink(for: pr)
        #expect(vm.copiedPRID == pr.id)

        // Wait for auto-dismiss (2s timeout + small buffer)
        try? await Task.sleep(for: .milliseconds(2200))
        #expect(vm.copiedPRID == nil)
    }

    @Test func copyingSecondPRReplacesFirst() {
        let pr1 = makePR(url: "https://github.com/owner/repo/pull/1")
        let pr2 = makePR(url: "https://github.com/owner/repo/pull/2")
        let vm = makeViewModel()

        vm.copyPRLink(for: pr1)
        vm.copyPRLink(for: pr2)

        #expect(vm.copiedPRID == pr2.id)
        let clipboard = NSPasteboard.general.string(forType: .string)
        #expect(clipboard == pr2.url)
    }
}
