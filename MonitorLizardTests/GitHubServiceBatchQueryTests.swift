import Testing
import Foundation
@testable import MonitorLizard

struct GitHubServiceBatchQueryTests {

    enum RequiredMetadataQueryScenario: CaseIterable, Sendable {
        case batch
        case batchDetail
        case detail

        var query: String {
            let request = PRStatusRequest(owner: "alice", repo: "repo", number: 42)
            switch self {
            case .batch:
                return GitHubService.buildBatchQuery(for: [request])
            case .batchDetail:
                return GitHubService.buildBatchDetailQuery(for: [request])
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

    @Test(arguments: RequiredMetadataQueryScenario.allCases)
    func queryIncludesStackMetadata(scenario: RequiredMetadataQueryScenario) {
        let query = scenario.query

        #expect(query.contains("stackEntry"))
        #expect(query.range(of: #"stackEntry\s*\{\s*position"#, options: .regularExpression) != nil)
        #expect(query.range(of: #"stack\s*\{\s*id\s+number\s+size\s*\}"#, options: .regularExpression) != nil)
    }

    @Test(arguments: RequiredMetadataQueryScenario.allCases)
    func queryOmitsStackMetadataWhenHostSchemaDoesNotSupportIt(scenario: RequiredMetadataQueryScenario) {
        let request = PRStatusRequest(owner: "alice", repo: "repo", number: 42)
        let query = switch scenario {
        case .batch:
            GitHubService.buildBatchQuery(for: [request], includeStackInfo: false)
        case .batchDetail:
            GitHubService.buildBatchDetailQuery(for: [request], includeStackInfo: false)
        case .detail:
            GitHubService.buildPRDetailQuery(for: request, includeStackInfo: false)
        }

        #expect(!query.contains("stackEntry"))
        #expect(query.contains("pr0"))
    }

    enum ViewerQueryScenario: CaseIterable, Sendable {
        case batch
        case batchDetail
        case detail

        func query(includeStackInfo: Bool) -> String {
            let request = PRStatusRequest(owner: "alice", repo: "repo", number: 42)
            switch self {
            case .batch:
                return GitHubService.buildBatchQuery(for: [request], includeStackInfo: includeStackInfo)
            case .batchDetail:
                return GitHubService.buildBatchDetailQuery(for: [request], includeStackInfo: includeStackInfo)
            case .detail:
                return GitHubService.buildPRDetailQuery(for: request, includeStackInfo: includeStackInfo)
            }
        }
    }

    @Test(arguments: ViewerQueryScenario.allCases, [true, false])
    func queryIncludesViewerLoginAndOpinionatedReviews(scenario: ViewerQueryScenario, includeStackInfo: Bool) {
        let query = scenario.query(includeStackInfo: includeStackInfo)

        #expect(query.range(of: #"viewer\s*\{\s*login\s*\}"#, options: .regularExpression) != nil)
        #expect(query.contains("latestOpinionatedReviews"))
        #expect(query.range(of: #"latestOpinionatedReviews[^{]*\{\s*nodes"#, options: .regularExpression) != nil)
    }

    @Test(arguments: ViewerQueryScenario.allCases)
    func queryRequestsOpinionatedReviewsWithTheSharedWindow(scenario: ViewerQueryScenario) {
        // The window size must come from the same constant `viewerApproved`
        // uses to judge truncation, so the request and its interpretation
        // cannot drift apart.
        let query = scenario.query(includeStackInfo: true)

        #expect(query.contains("latestOpinionatedReviews(last: \(BatchPRStatusResponse.reviewConnectionWindow))"))
    }

    @Test func buildBatchQueryForEmptyListProducesValidQuery() {
        let query = GitHubService.buildBatchQuery(for: [])
        #expect(query.contains("query"))
    }

    @Test func detectsStackUnsupportedSchemaErrors() {
        for message in [
            "gh: Field 'stackEntry' doesn't exist on type 'PullRequest'",
            "GraphQL: Field 'stackEntry' does not exist on type 'PullRequest'",
            "Unknown field 'stackEntry' on type 'PullRequest'",
            "Cannot query field \"stackEntry\" on type \"PullRequest\".",
            "Field 'stackEntry' not defined on type 'PullRequest'",
            "No such field 'stackEntry' on type 'PullRequest'",
            "Unrecognized field 'stackEntry' on type 'PullRequest'",
            "Undefined field 'stackEntry' on type 'PullRequest'",
        ] {
            #expect(GitHubService.isStackInfoUnsupportedError(ShellError.executionFailed(message)))
        }

        #expect(!GitHubService.isStackInfoUnsupportedError(ShellError.executionFailed("error connecting to api.github.com")))
        #expect(!GitHubService.isStackInfoUnsupportedError(ShellError.networkError("offline")))
        #expect(!GitHubService.isStackInfoUnsupportedError(ShellError.invalidOutput))
        #expect(!GitHubService.isStackInfoUnsupportedError(GitHubError.invalidResponse))
    }

    @Test func buildBatchQueryUsesIndexBasedAliases() {
        let requests = (0..<5).map { PRStatusRequest(owner: "o", repo: "r", number: $0) }
        let query = GitHubService.buildBatchQuery(for: requests)
        for i in 0..<5 {
            #expect(query.contains("pr\(i)"))
        }
    }

    // MARK: - Batch detail query

    @Test func buildBatchDetailQueryAliasesEveryRequestAndSelectsTheFullDetail() {
        let requests = [
            PRStatusRequest(owner: "acme", repo: "widget", number: 101),
            PRStatusRequest(owner: "acme", repo: "widget", number: 104),
        ]
        let query = GitHubService.buildBatchDetailQuery(for: requests)

        #expect(query.contains("pr0: repository(owner: \"acme\", name: \"widget\")"))
        #expect(query.contains("pr1: repository(owner: \"acme\", name: \"widget\")"))
        #expect(query.contains("pullRequest(number: 101)"))
        #expect(query.contains("pullRequest(number: 104)"))
        // The full detail selection, so a PullRequest can be built per part.
        for field in [
            "number", "title", "url", "author { login }", "updatedAt", "labels(first: 20)",
            "isDraft", "state", "headRefName", "baseRef", "branchProtectionRule",
            "statusCheckRollup", "mergeable", "mergeStateStatus", "reviewDecision",
            "latestReviews", "latestOpinionatedReviews", "reviewRequests",
        ] {
            #expect(query.contains(field), "missing field: \(field)")
        }
        #expect(query.range(of: #"viewer\s*\{\s*login\s*\}"#, options: .regularExpression) != nil)
    }

    @Test func buildPRDetailQueryDelegatesToTheBatchDetailBuilder() {
        let request = PRStatusRequest(owner: "alice", repo: "repo", number: 42)

        #expect(GitHubService.buildPRDetailQuery(for: request)
            == GitHubService.buildBatchDetailQuery(for: [request]))
        #expect(GitHubService.buildPRDetailQuery(for: request, includeStackInfo: false)
            == GitHubService.buildBatchDetailQuery(for: [request], includeStackInfo: false))
    }
}
