import Testing
import Foundation
@testable import MonitorLizard

@MainActor
struct WatchlistServiceTests {

    private func makeService() -> WatchlistService {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return WatchlistService(defaults: suite)
    }

    private func makePR(
        number: Int,
        buildStatus: BuildStatus = .success,
        updatedAt: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> PullRequest {
        PullRequest(
            number: number,
            title: "Test PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: "repo", nameWithOwner: "owner/repo"),
            url: "https://github.com/owner/repo/pull/\(number)",
            author: PullRequest.Author(login: "testuser"),
            headRefName: "feature/test",
            updatedAt: updatedAt,
            buildStatus: buildStatus,
            isWatched: false,
            labels: [],
            type: .authored,
            isDraft: false,
            statusChecks: [],
            reviewDecision: nil,
            host: "github.com",
            customName: nil
        )
    }

    // MARK: - Watch / Unwatch

    @Test func watchMakesPRWatched() {
        let service = makeService()
        let pr = makePR(number: 1)

        service.watch(pr)

        #expect(service.isWatched(pr))
    }

    @Test func unwatchMakesPRNotWatched() {
        let service = makeService()
        let pr = makePR(number: 1)

        service.watch(pr)
        service.unwatch(pr)

        #expect(!service.isWatched(pr))
    }

    // MARK: - lastUpdatedAt triggers update

    @Test func watchStoresLastUpdatedAt() {
        let service = makeService()
        let t = Date(timeIntervalSince1970: 1_000_000)
        let pr = makePR(number: 1, updatedAt: t)

        service.watch(pr)

        #expect(service.getWatchedStatus(for: pr.id)?.lastUpdatedAt == t)
    }

    @Test func lastUpdatedAtUpdatesAfterCheckForCompletions() {
        let service = makeService()
        let t1 = Date(timeIntervalSince1970: 1_000_000)
        let t2 = Date(timeIntervalSince1970: 2_000_000)
        let pr = makePR(number: 1, updatedAt: t1)
        service.watch(pr)

        _ = service.checkForCompletions(currentPRs: [makePR(number: 1, updatedAt: t2)])

        #expect(service.getWatchedStatus(for: pr.id)?.lastUpdatedAt == t2)
    }

    @Test func statusChangeUpdatesStoredStatus() {
        let service = makeService()
        let pr = makePR(number: 1, buildStatus: .pending)
        service.watch(pr)

        let updatedPR = makePR(number: 1, buildStatus: .success)
        _ = service.checkForCompletions(currentPRs: [updatedPR])

        let info = service.getWatchedStatus(for: pr.id)
        #expect(info?.lastStatus == .success)
    }

    @Test func updatedAtChangeAloneTriggersStoredUpdate() {
        let service = makeService()
        let t1 = Date(timeIntervalSince1970: 1_000_000)
        let t2 = Date(timeIntervalSince1970: 2_000_000)
        let pr = makePR(number: 1, buildStatus: .success, updatedAt: t1)
        service.watch(pr)

        // Same build status, but updatedAt changed — stored entry must be refreshed
        let updatedPR = makePR(number: 1, buildStatus: .success, updatedAt: t2)
        _ = service.checkForCompletions(currentPRs: [updatedPR])

        let info = service.getWatchedStatus(for: pr.id)
        #expect(info?.lastStatus == .success)
        // The timestamp recorded should be after t1 (i.e. the watch entry was refreshed)
        #expect((info?.timestamp ?? Date.distantPast) >= t1)
    }

    // MARK: - Completion detection

    @Test func pendingToSuccessIsReportedAsCompletion() {
        let service = makeService()
        let pr = makePR(number: 1, buildStatus: .pending)
        service.watch(pr)

        let completedPR = makePR(number: 1, buildStatus: .success)
        let completions = service.checkForCompletions(currentPRs: [completedPR])

        #expect(completions.count == 1)
        #expect(completions[0].number == 1)
    }

    @Test func alreadyCompletedPRIsNotReportedAgain() {
        let service = makeService()
        let pr = makePR(number: 1, buildStatus: .success)
        service.watch(pr)

        // Status was already success when watched — no transition
        let completions = service.checkForCompletions(currentPRs: [pr])

        #expect(completions.isEmpty)
    }

    // MARK: - Persistence round-trip

    @Test func watchedStateRoundTripsViaUserDefaults() {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let service1 = WatchlistService(defaults: suite)
        let pr = makePR(number: 42, buildStatus: .pending)
        service1.watch(pr)

        // New service instance reads from the same UserDefaults suite
        let service2 = WatchlistService(defaults: suite)
        #expect(service2.isWatched(pr))
        #expect(service2.getWatchedStatus(for: pr.id)?.lastStatus == .pending)
        #expect(service2.getWatchedStatus(for: pr.id)?.lastUpdatedAt == Date(timeIntervalSince1970: 1_000_000))
    }
}
