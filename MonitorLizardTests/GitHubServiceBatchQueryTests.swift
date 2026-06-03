import Testing
import Foundation
@testable import MonitorLizard

struct GitHubServiceBatchQueryTests {

    enum RequiredMetadataQueryScenario: CaseIterable, Sendable {
        case batch
        case detail

        var query: String {
            let request = PRStatusRequest(owner: "alice", repo: "repo", number: 42)
            switch self {
            case .batch:
                return GitHubService.buildBatchQuery(for: [request])
            case .detail:
                return GitHubService.buildPRDetailQuery(for: request)
            }
        }
    }

    @Test func buildBatchQueryContainsAllPRs() {
        let requests = [
            PRStatusRequest(owner: "alice", repo: "widgets", number: 42),
            PRStatusRequest(owner: "bob", repo: "gadgets", number: 7),
        ]
        let query = GitHubService.buildBatchQuery(for: requests)
        #expect(query.contains("pr0"))
        #expect(query.contains("pr1"))
        #expect(query.contains("\"alice\""))
        #expect(query.contains("\"widgets\""))
        #expect(query.contains("42"))
        #expect(query.contains("\"bob\""))
        #expect(query.contains("\"gadgets\""))
        #expect(query.contains("7"))
    }

    @Test func buildBatchQueryIncludesRequiredStatusFields() {
        let query = GitHubService.buildBatchQuery(for: [
            PRStatusRequest(owner: "alice", repo: "repo", number: 1)
        ])
        #expect(query.contains("headRefName"))
        #expect(query.contains("statusCheckRollup"))
        #expect(query.range(of: #"statusCheckRollup\s*\{\s*state"#, options: .regularExpression) != nil)
        #expect(query.contains("mergeable"))
        #expect(query.contains("mergeStateStatus"))
        #expect(query.contains("reviewDecision"))
        #expect(query.contains("latestReviews"))
        #expect(query.contains("reviewRequests"))
    }

    @Test(arguments: RequiredMetadataQueryScenario.allCases)
    func queryIncludesRequiredCheckMetadata(scenario: RequiredMetadataQueryScenario) {
        let query = scenario.query

        #expect(query.contains("isRequired(pullRequestNumber: 42)"))
        #expect(query.components(separatedBy: "isRequired(pullRequestNumber: 42)").count - 1 == 2)
        #expect(query.contains("baseRef"))
        #expect(query.contains("branchProtectionRule"))
        #expect(query.contains("requiredStatusCheckContexts"))
        #expect(query.contains("requiredStatusChecks"))
        #expect(query.range(of: #"statusCheckRollup\s*\{\s*state"#, options: .regularExpression) != nil)
    }

    @Test func buildBatchQueryForEmptyListProducesValidQuery() {
        let query = GitHubService.buildBatchQuery(for: [])
        #expect(query.contains("query"))
    }

    @Test func buildBatchQueryUsesIndexBasedAliases() {
        let requests = (0..<5).map { PRStatusRequest(owner: "o", repo: "r", number: $0) }
        let query = GitHubService.buildBatchQuery(for: requests)
        for i in 0..<5 {
            #expect(query.contains("pr\(i)"))
        }
    }
}