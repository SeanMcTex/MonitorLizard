import Testing
import Foundation
@testable import MonitorLizard

@MainActor
struct PRCacheServiceTests {

    private func makeService() -> PRCacheService {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return PRCacheService(defaults: suite)
    }

    private func makePR(number: Int, isWatched: Bool = false, type: PRType = .authored) -> PullRequest {
        PullRequest(
            number: number,
            title: "Test PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: "repo", nameWithOwner: "owner/repo"),
            url: "https://github.com/owner/repo/pull/\(number)",
            author: PullRequest.Author(login: "testuser"),
            headRefName: "feature/test",
            updatedAt: Date(timeIntervalSince1970: 1_000_000),
            buildStatus: .success,
            isWatched: isWatched,
            labels: [],
            type: type,
            isDraft: false,
            statusChecks: [],
            reviewDecision: nil,
            host: "github.com",
            customName: nil
        )
    }

    // MARK: Empty state

    @Test func emptyOnFirstLaunch() {
        let service = makeService()
        #expect(service.loadMainPRs().isEmpty)
        #expect(service.loadOtherPRs().isEmpty)
    }

    // MARK: Round-trip

    @Test func roundTripMainPRs() {
        let service = makeService()
        service.save(mainPRs: [makePR(number: 1), makePR(number: 2)], otherPRs: [])
        let loaded = service.loadMainPRs()
        #expect(loaded.map(\.number) == [1, 2])
    }

    @Test func roundTripOtherPRs() {
        let service = makeService()
        service.save(mainPRs: [], otherPRs: [makePR(number: 3, type: .other)])
        let loaded = service.loadOtherPRs()
        #expect(loaded.map(\.number) == [3])
    }

    @Test func preservesKeyFields() {
        let service = makeService()
        let pr = PullRequest(
            number: 42,
            title: "Important PR",
            repository: PullRequest.RepositoryInfo(name: "myrepo", nameWithOwner: "org/myrepo"),
            url: "https://github.com/org/myrepo/pull/42",
            author: PullRequest.Author(login: "alice"),
            headRefName: "feature/cool",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            buildStatus: .failure,
            isWatched: true,
            labels: [PullRequest.Label(id: "lb1", name: "bug", color: "d73a4a")],
            type: .reviewing,
            isDraft: true,
            statusChecks: [],
            reviewDecision: .approved,
            host: "github.com",
            customName: "My Custom Name"
        )

        service.save(mainPRs: [pr], otherPRs: [])
        let loaded = service.loadMainPRs()[0]

        #expect(loaded.number == 42)
        #expect(loaded.title == "Important PR")
        #expect(loaded.repository.nameWithOwner == "org/myrepo")
        #expect(loaded.author.login == "alice")
        #expect(loaded.buildStatus == .failure)
        #expect(loaded.isWatched == true)
        #expect(loaded.labels.count == 1)
        #expect(loaded.labels[0].name == "bug")
        #expect(loaded.type == .reviewing)
        #expect(loaded.isDraft == true)
        #expect(loaded.reviewDecision == .approved)
        #expect(loaded.customName == "My Custom Name")
    }

    // MARK: Overwrite

    @Test func subsequentSaveOverwritesPrevious() {
        let service = makeService()
        service.save(mainPRs: [makePR(number: 1)], otherPRs: [])
        service.save(mainPRs: [makePR(number: 2), makePR(number: 3)], otherPRs: [])
        let loaded = service.loadMainPRs()
        #expect(loaded.map(\.number) == [2, 3])
    }

    @Test func savingEmptyListClearsPreviousData() {
        let service = makeService()
        service.save(mainPRs: [makePR(number: 1)], otherPRs: [makePR(number: 2)])
        service.save(mainPRs: [], otherPRs: [])
        #expect(service.loadMainPRs().isEmpty)
        #expect(service.loadOtherPRs().isEmpty)
    }

    // MARK: Hash guard

    @Test func hashGuardDoesNotCorruptDataOnRepeatedSave() {
        let service = makeService()
        let prs = [makePR(number: 1)]
        service.save(mainPRs: prs, otherPRs: [])
        service.save(mainPRs: prs, otherPRs: []) // same data — hash guard skips write
        #expect(service.loadMainPRs().map(\.number) == [1])
    }
}
