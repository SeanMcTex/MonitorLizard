import Testing
import Foundation
@testable import MonitorLizard

@MainActor
struct NonBlockingCheckSummaryTests {

    enum NilSummaryScenario: CaseIterable, Sendable {
        case requiredOnly
        case unknownRequiredness
        case allNonBlockingChecksPassed
        case nonRequiredCheckNotMarkedNonBlocking

        @MainActor
        var statusChecks: [StatusCheck] {
            switch self {
            case .requiredOnly:
                return [Self.check(id: "required", status: .success, isRequired: true, isNonBlocking: false)]
            case .unknownRequiredness:
                return [Self.check(id: "unknown", status: .pending, isRequired: nil, isNonBlocking: false)]
            case .allNonBlockingChecksPassed:
                return [Self.check(id: "optional", status: .success)]
            case .nonRequiredCheckNotMarkedNonBlocking:
                return [Self.check(id: "required-workflow-job", status: .running, isNonBlocking: false)]
            }
        }

        @MainActor
        private static func check(id: String, status: CheckStatus, isRequired: Bool? = false, isNonBlocking: Bool = true) -> StatusCheck {
            StatusCheck(id: id, name: id, status: status, detailsUrl: nil, isRequired: isRequired, isNonBlocking: isNonBlocking)
        }
    }

    enum SegmentSummaryScenario: CaseIterable, Sendable {
        case waitingAndRunning
        case allActionableStates
        case failedWithPassedCheck

        @MainActor
        var statusChecks: [StatusCheck] {
            switch self {
            case .waitingAndRunning:
                return [
                    Self.check(id: "approval", status: .waiting),
                    Self.check(id: "analysis", status: .running),
                ]
            case .allActionableStates:
                return [
                    Self.check(id: "optional-failed", status: .failure),
                    Self.check(id: "optional-error", status: .error),
                    Self.check(id: "optional-waiting", status: .waiting),
                    Self.check(id: "optional-running", status: .running),
                    Self.check(id: "optional-queued", status: .queued),
                    Self.check(id: "optional-pending", status: .pending),
                    Self.check(id: "optional-success", status: .success),
                    Self.check(id: "optional-skipped", status: .skipped),
                ]
            case .failedWithPassedCheck:
                return [
                    Self.check(id: "optional-failed", status: .failure),
                    Self.check(id: "optional-passed", status: .success),
                ]
            }
        }

        var expectedSegments: [String] {
            switch self {
            case .waitingAndRunning:
                return ["1 waiting for approval", "1 running"]
            case .allActionableStates:
                return ["2 failed", "1 waiting for approval", "1 running", "1 queued", "1 pending"]
            case .failedWithPassedCheck:
                return ["1 failed"]
            }
        }

        @MainActor
        private static func check(id: String, status: CheckStatus) -> StatusCheck {
            StatusCheck(id: id, name: id, status: status, detailsUrl: nil, isRequired: false, isNonBlocking: true)
        }
    }

    private func makePR(statusChecks: [StatusCheck]) -> PullRequest {
        PullRequest(
            number: 1,
            title: "Test PR",
            repository: PullRequest.RepositoryInfo(name: "repo", nameWithOwner: "owner/repo"),
            url: "https://github.com/owner/repo/pull/1",
            author: PullRequest.Author(login: "author"),
            headRefName: "feature/test",
            updatedAt: Date(),
            buildStatus: .success,
            isWatched: false,
            labels: [],
            type: .authored,
            isDraft: false,
            statusChecks: statusChecks,
            reviewDecision: nil,
            host: "github.com"
        )
    }

    @Test(arguments: NilSummaryScenario.allCases)
    func summaryIsNil(scenario: NilSummaryScenario) {
        let pr = makePR(statusChecks: scenario.statusChecks)

        #expect(pr.nonBlockingCheckSummary == nil)
    }

    @Test(arguments: SegmentSummaryScenario.allCases)
    func summarySegmentsMatchExpected(scenario: SegmentSummaryScenario) throws {
        let pr = makePR(statusChecks: scenario.statusChecks)

        let summary = try #require(pr.nonBlockingCheckSummary)

        #expect(summary.segments.map(\.text) == scenario.expectedSegments)
    }
}