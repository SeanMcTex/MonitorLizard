import Testing
import Foundation
@testable import MonitorLizard

// MARK: - Build Status Presentation Tests

struct BuildStatusPresentationTests {

    private static let presentations: [(status: BuildStatus, displayName: String, icon: String, systemImageName: String?)] = [
        (.conflict, "Merge Conflict", "❗", nil),
        (.notStarted, "Not started", "🛑", "play.slash"),
        (.pending, "Pending", "🔄", "gear"),
        (.success, "Success", "✅", "gear.badge.checkmark"),
        (.failure, "Failed", "❌", "gear.badge.xmark"),
        (.error, "Error", "⚠️", "gear.badge.xmark"),
        (.unknown, "Unknown", "❓", nil),
        (.inactive, "Inactive", "⏳", nil),
    ]

    @Test func buildStatusPresentationCoversEveryState() {
        #expect(Self.presentations.map(\.status) == BuildStatus.allCases)
    }

    @Test(arguments: BuildStatusPresentationTests.presentations)
    @MainActor
    func buildStatusPresentationMatchesExpected(status: BuildStatus, displayName: String, icon: String, systemImageName: String?) {
        #expect(status.displayName == displayName)
        #expect(status.icon == icon)
        #expect(status.systemImageName == systemImageName)
    }
}

// MARK: - Non-blocking Check Summary Tests

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

// MARK: - Mock

private actor MockShellExecutor: ShellExecuting {
    private(set) var getAuthenticatedHostsCallCount = 0
    private(set) var executeCalls: [(command: String, arguments: [String])] = []

    private let defaultResponse: Result<String, Error>
    // Checked in order; first matcher whose string appears in the joined arguments wins.
    private let responseMatchers: [(matcher: String, response: Result<String, Error>)]

    init(
        executeResponse: Result<String, Error> = .success("[]"),
        executeResponseMatchers: [(String, Result<String, Error>)] = []
    ) {
        self.defaultResponse = executeResponse
        self.responseMatchers = executeResponseMatchers.map { (matcher: $0.0, response: $0.1) }
    }

    func execute(command: String, arguments: [String], timeout: TimeInterval, host: String?) async throws -> String {
        executeCalls.append((command: command, arguments: arguments))
        let argString = arguments.joined(separator: " ")
        for (matcher, response) in responseMatchers {
            if argString.contains(matcher) {
                return try response.get()
            }
        }
        return try defaultResponse.get()
    }

    func getAuthenticatedHosts() async throws -> [String] {
        getAuthenticatedHostsCallCount += 1
        return ["github.com"]
    }

    func checkGHInstalled() async throws -> Bool { true }
    func checkGHAuthenticated() async throws -> Bool { true }
}

// MARK: - Host Cache Tests

@MainActor
struct GitHubServiceHostCacheTests {

    @Test func hostsAreCachedAfterFirstFetch() async throws {
        let mock = MockShellExecutor()
        let service = GitHubService(shellExecutor: mock)

        _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        #expect(await mock.getAuthenticatedHostsCallCount == 1)

        _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        #expect(await mock.getAuthenticatedHostsCallCount == 1, "second fetch should use the cached hosts")
    }

    @Test func invalidateHostsCacheForcesRefetch() async throws {
        let mock = MockShellExecutor()
        let service = GitHubService(shellExecutor: mock)

        _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        #expect(await mock.getAuthenticatedHostsCallCount == 1)

        service.invalidateHostsCache()

        _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        #expect(await mock.getAuthenticatedHostsCallCount == 2, "invalidated cache should trigger a re-fetch")
    }
}

// MARK: - Fetch Error Rethrow Tests

@MainActor
struct GitHubServiceFetchErrorTests {

    enum GitHubErrorMappingScenario: CaseIterable, Sendable {
        case networkError
        case commandNotFound

        var shellError: ShellError {
            switch self {
            case .networkError:
                return .networkError("error connecting to api.github.com")
            case .commandNotFound:
                return .commandNotFound
            }
        }

        var expectedError: GitHubError {
            switch self {
            case .networkError:
                return .networkError
            case .commandNotFound:
                return .notInstalled
            }
        }
    }

    /// When all fetches fail with a generic execution error (e.g. auth expired), the original
    /// ShellError should propagate — not be swallowed into GitHubError.networkError.
    @Test func executionFailureRethrowsAsShellError() async {
        let mock = MockShellExecutor(executeResponse: .failure(ShellError.executionFailed("token expired or invalid")))
        let service = GitHubService(shellExecutor: mock)

        do {
            _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
            Issue.record("Expected an error to be thrown")
        } catch let error as GitHubError where error == .networkError {
            Issue.record("executionFailed should not be re-mapped to GitHubError.networkError")
        } catch is ShellError {
            // Expected: original ShellError re-thrown as-is
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test(arguments: GitHubErrorMappingScenario.allCases)
    func shellFailureMapsToExpectedGitHubError(scenario: GitHubErrorMappingScenario) async {
        let mock = MockShellExecutor(executeResponse: .failure(scenario.shellError))
        let service = GitHubService(shellExecutor: mock)

        do {
            _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
            Issue.record("Expected an error to be thrown")
        } catch let error as GitHubError {
            #expect(error == scenario.expectedError)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Batch Query Building Tests

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

// MARK: - Batch Response Parsing Tests

@MainActor
struct GitHubServiceBatchResponseParsingTests {

    private static func makeResponse(headRefName: String = "main", reviewDecision: String? = nil) -> String {
        let decision = reviewDecision.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "data": {
            "pr0": {
              "pullRequest": {
                "headRefName": "\(headRefName)",
                "statusCheckRollup": null,
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "CLEAN",
                "reviewDecision": \(decision),
                "latestReviews": { "nodes": [] },
                "reviewRequests": { "nodes": [] }
              }
            }
          }
        }
        """
    }

    @Test func parseBatchResponseExtractsHeadRefName() throws {
        let request = PRStatusRequest(owner: "alice", repo: "widgets", number: 42)
        let result = try GitHubService.parseBatchResponse(
            Self.makeResponse(headRefName: "feature/my-branch"), requests: [request]
        )
        #expect(result[request]?.headRefName == "feature/my-branch")
    }

    @Test func parseBatchResponseExtractsReviewDecision() throws {
        let request = PRStatusRequest(owner: "alice", repo: "widgets", number: 42)
        let result = try GitHubService.parseBatchResponse(
            Self.makeResponse(reviewDecision: "APPROVED"), requests: [request]
        )
        #expect(result[request]?.reviewDecision == "APPROVED")
    }

    @Test func parseBatchResponseHandlesNullPullRequest() throws {
        let json = """
        { "data": { "pr0": { "pullRequest": null } } }
        """
        let request = PRStatusRequest(owner: "alice", repo: "widgets", number: 42)
        let result = try GitHubService.parseBatchResponse(json, requests: [request])
        #expect(result[request] == nil, "closed or missing PRs should be absent from the result")
    }

    @Test func parseBatchResponseHandlesMultiplePRsAcrossRepos() throws {
        let json = """
        {
          "data": {
            "pr0": { "pullRequest": { "headRefName": "branch-a", "statusCheckRollup": null, "mergeable": null, "mergeStateStatus": null, "reviewDecision": null, "latestReviews": { "nodes": [] }, "reviewRequests": { "nodes": [] } } },
            "pr1": { "pullRequest": { "headRefName": "branch-b", "statusCheckRollup": null, "mergeable": null, "mergeStateStatus": null, "reviewDecision": null, "latestReviews": { "nodes": [] }, "reviewRequests": { "nodes": [] } } }
          }
        }
        """
        let req0 = PRStatusRequest(owner: "alice", repo: "widgets", number: 1)
        let req1 = PRStatusRequest(owner: "bob", repo: "gadgets", number: 2)
        let result = try GitHubService.parseBatchResponse(json, requests: [req0, req1])
        #expect(result[req0]?.headRefName == "branch-a")
        #expect(result[req1]?.headRefName == "branch-b")
    }

    @Test func parseBatchResponsePreservesStatusChecks() throws {
        let json = """
        {
          "data": {
            "pr0": {
              "pullRequest": {
                "headRefName": "main",
                "statusCheckRollup": {
                  "contexts": {
                    "nodes": [
                      { "__typename": "CheckRun", "name": "CI", "status": "COMPLETED", "conclusion": "SUCCESS", "detailsUrl": "https://ci.example.com", "context": null, "state": null, "targetUrl": null }
                    ]
                  }
                },
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "CLEAN",
                "reviewDecision": null,
                "latestReviews": { "nodes": [] },
                "reviewRequests": { "nodes": [] }
              }
            }
          }
        }
        """
        let request = PRStatusRequest(owner: "alice", repo: "repo", number: 1)
        let result = try GitHubService.parseBatchResponse(json, requests: [request])
        #expect(result[request]?.statusCheckRollup?.count == 1)
        #expect(result[request]?.statusCheckRollup?.first?.name == "CI")
        #expect(result[request]?.statusCheckRollup?.first?.conclusion == "SUCCESS")
    }

    @Test func parseBatchResponseFlattensReviewConnections() throws {
        let json = """
        {
          "data": {
            "pr0": {
              "pullRequest": {
                "headRefName": "main",
                "statusCheckRollup": null,
                "mergeable": null,
                "mergeStateStatus": null,
                "reviewDecision": "CHANGES_REQUESTED",
                "latestReviews": {
                  "nodes": [{ "state": "CHANGES_REQUESTED", "author": { "login": "alice" } }]
                },
                "reviewRequests": {
                  "nodes": [{ "requestedReviewer": { "login": "alice" } }]
                }
              }
            }
          }
        }
        """
        let request = PRStatusRequest(owner: "owner", repo: "repo", number: 1)
        let result = try GitHubService.parseBatchResponse(json, requests: [request])
        let detail = result[request]
        #expect(detail?.latestReviews?.first?.state == "CHANGES_REQUESTED")
        #expect(detail?.latestReviews?.first?.author?.login == "alice")
        #expect(detail?.reviewRequests?.first?.login == "alice")
    }

    @Test func parseBatchResponseHandlesTeamReviewRequestsGracefully() throws {
        // Team reviewers have no User login — requestedReviewer decodes as { login: null }
        let json = """
        {
          "data": {
            "pr0": {
              "pullRequest": {
                "headRefName": "main",
                "statusCheckRollup": null,
                "mergeable": null,
                "mergeStateStatus": null,
                "reviewDecision": "REVIEW_REQUIRED",
                "latestReviews": { "nodes": [] },
                "reviewRequests": {
                  "nodes": [{ "requestedReviewer": {} }]
                }
              }
            }
          }
        }
        """
        let request = PRStatusRequest(owner: "owner", repo: "repo", number: 1)
        let result = try GitHubService.parseBatchResponse(json, requests: [request])
        #expect(result[request]?.reviewRequests?.first?.login == nil)
    }

    @Test func parseBatchResponseUnionsAndDeduplicatesRequiredStatusContexts() throws {
        let json = """
        {
          "data": {
            "pr0": {
              "pullRequest": {
                "headRefName": "main",
                "statusCheckRollup": null,
                "mergeable": null,
                "mergeStateStatus": null,
                "reviewDecision": null,
                "latestReviews": { "nodes": [] },
                "reviewRequests": { "nodes": [] },
                "baseRef": {
                  "branchProtectionRule": {
                    "requiredStatusCheckContexts": ["legacy_ci", "duplicate_ci"],
                    "requiredStatusChecks": [{ "context": "modern_ci" }, { "context": "duplicate_ci" }]
                  }
                }
              }
            }
          }
        }
        """
        let request = PRStatusRequest(owner: "owner", repo: "repo", number: 1)

        let result = try GitHubService.parseBatchResponse(json, requests: [request])
        let contexts = try #require(result[request]?.requiredStatusCheckContexts)

        #expect(Set(contexts) == ["legacy_ci", "modern_ci", "duplicate_ci"])
        #expect(contexts.count == 3)
        #expect(contexts == contexts.sorted())
    }

    @Test func parseBatchResponseLeavesRequiredContextsNilWithoutBranchProtectionRule() throws {
        let json = """
        {
          "data": {
            "pr0": {
              "pullRequest": {
                "headRefName": "main",
                "statusCheckRollup": null,
                "mergeable": null,
                "mergeStateStatus": null,
                "reviewDecision": null,
                "latestReviews": { "nodes": [] },
                "reviewRequests": { "nodes": [] },
                "baseRef": { "branchProtectionRule": null }
              }
            }
          }
        }
        """
        let request = PRStatusRequest(owner: "owner", repo: "repo", number: 1)

        let result = try GitHubService.parseBatchResponse(json, requests: [request])

        #expect(result[request]?.requiredStatusCheckContexts == nil)
    }
}

// MARK: - Batch Integration Tests

@MainActor
struct GitHubServiceBatchIntegrationTests {

    // Minimal valid search result (one PR)
    private static let authoredSearchResult = """
    [{
      "number": 1,
      "title": "Add feature",
      "repository": { "name": "repo", "nameWithOwner": "alice/repo" },
      "url": "https://github.com/alice/repo/pull/1",
      "author": { "login": "alice" },
      "updatedAt": "2024-01-01T00:00:00Z",
      "labels": [],
      "isDraft": false
    }]
    """

    private static let batchStatusResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": null,
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] }
          }
        }
      }
    }
    """

    private static func rollupStateOnlyResult(state: String) -> String {
        """
        {
          "data": {
            "pr0": {
              "pullRequest": {
                "headRefName": "feature/test",
                "statusCheckRollup": {
                  "state": "\(state)",
                  "contexts": { "nodes": [] }
                },
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "CLEAN",
                "reviewDecision": null,
                "latestReviews": { "nodes": [] },
                "reviewRequests": { "nodes": [] },
                "baseRef": { "branchProtectionRule": null }
              }
            }
          }
        }
        """
    }

    private static let requiredSuccessOptionalPendingResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "required_ci", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://ci.example.com/required", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "manual_approval", "status": "WAITING", "conclusion": null, "isRequired": false, "detailsUrl": "https://ci.example.com/manual", "context": null, "state": null, "targetUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["required_ci"],
                "requiredStatusChecks": [{ "context": "required_ci" }]
              }
            }
          }
        }
      }
    }
    """

    private static let requiredSuccessOptionalFailureResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "required_ci", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://ci.example.com/required", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "manual_approval", "status": "COMPLETED", "conclusion": "FAILURE", "isRequired": false, "detailsUrl": "https://ci.example.com/manual", "context": null, "state": null, "targetUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["required_ci"],
                "requiredStatusChecks": [{ "context": "required_ci" }]
              }
            }
          }
        }
      }
    }
    """

    private static let optionalApprovalNamedStatusContextResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "required_ci", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://ci.example.com/required", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "isRequired": false, "context": "ci/example: approval_tests", "state": "PENDING", "targetUrl": "https://ci.example.com/approval-tests", "detailsUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["required_ci"],
                "requiredStatusChecks": [{ "context": "required_ci" }]
              }
            }
          }
        }
      }
    }
    """

    private static let branchProtectionRequirednessFallbackResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "required_ci", "status": "COMPLETED", "conclusion": "SUCCESS", "detailsUrl": "https://ci.example.com/required", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "optional_ci", "status": "PENDING", "conclusion": null, "detailsUrl": "https://ci.example.com/optional", "context": null, "state": null, "targetUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["required_ci"],
                "requiredStatusChecks": [{ "context": "required_ci" }]
              }
            }
          }
        }
      }
    }
    """

    private static let requiredSuccessWaitingApprovalParentResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "required_ci", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://ci.example.com/required", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "deploy", "status": "WAITING", "conclusion": null, "isRequired": false, "detailsUrl": "https://ci.example.com/deploy", "context": null, "state": null, "targetUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["required_ci"],
                "requiredStatusChecks": [{ "context": "required_ci" }]
              }
            }
          }
        }
      }
    }
    """

    private static let waitingCheckRunApprovalResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "required_ci", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://ci.example.com/required", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "deploy / wait_for_approval", "status": "WAITING", "conclusion": null, "isRequired": false, "detailsUrl": "https://ci.example.com/deploy/wait", "context": null, "state": null, "targetUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["required_ci"],
                "requiredStatusChecks": [{ "context": "required_ci" }]
              }
            }
          }
        }
      }
    }
    """

    private static let requiredApprovalGateDoesNotSuppressOptionalParentResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "required_ci", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://ci.example.com/required", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "deploy", "status": "IN_PROGRESS", "conclusion": null, "isRequired": false, "detailsUrl": "https://ci.example.com/deploy", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "isRequired": true, "context": "ci/example: deploy/approve_deploy", "state": "PENDING", "targetUrl": "https://ci.example.com/deploy/approve", "detailsUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "BLOCKED",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["required_ci", "ci/example: deploy/approve_deploy"],
                "requiredStatusChecks": [{ "context": "required_ci" }, { "context": "ci/example: deploy/approve_deploy" }]
              }
            }
          }
        }
      }
    }
    """

    private static let missingRequiredMetadataPendingResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "unknown_ci", "status": "WAITING", "conclusion": null, "detailsUrl": "https://ci.example.com/unknown", "context": null, "state": null, "targetUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": { "branchProtectionRule": null }
          }
        }
      }
    }
    """

    private static let requiredContextMissingApprovalWaitingResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "state": "FAILURE",
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "version_health / assessment", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://github.com/example/version-health", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "isRequired": false, "context": "ci/circleci: preflight_check", "state": "FAILURE", "targetUrl": "https://circleci.com/gh/owner/repo/105140", "detailsUrl": null },
                  { "__typename": "CheckRun", "name": "pull_requests", "status": "COMPLETED", "conclusion": "FAILURE", "isRequired": false, "detailsUrl": "https://app.circleci.com/pipelines/gh/owner/repo/1/workflows/required", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "dead_code_cleanup", "status": "IN_PROGRESS", "conclusion": null, "isRequired": false, "detailsUrl": "https://app.circleci.com/pipelines/gh/owner/repo/1/workflows/optional", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "dead_code_cleanup / approve", "status": "WAITING", "conclusion": null, "isRequired": false, "detailsUrl": "https://ci.example.com/workflows/optional/approve", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "context": "ci/circleci: check_mobsfscan", "state": "SUCCESS", "targetUrl": "https://circleci.com/gh/owner/repo/101", "detailsUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "context": "ci/circleci: check_circleci_config_lint", "state": "SUCCESS", "targetUrl": "https://circleci.com/gh/owner/repo/101", "detailsUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "BLOCKED",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["ci/circleci: required_jobs_met", "version_health / assessment"],
                "requiredStatusChecks": [{ "context": "ci/circleci: required_jobs_met" }, { "context": "version_health / assessment" }]
              }
            }
          }
        }
      }
    }
    """

    private static let missingRequiredContextWithWaitingApprovalParentResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "state": "PENDING",
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "version_health / assessment", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://github.com/example/version-health", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "deploy", "status": "WAITING", "conclusion": null, "isRequired": false, "detailsUrl": "https://ci.example.com/deploy", "context": null, "state": null, "targetUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "BLOCKED",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["ci/example: required_jobs_met", "version_health / assessment"],
                "requiredStatusChecks": [{ "context": "ci/example: required_jobs_met" }, { "context": "version_health / assessment" }]
              }
            }
          }
        }
      }
    }
    """

    private static let requiredContextMissingErrorResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "state": "ERROR",
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "version_health / assessment", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://github.com/example/version-health", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "isRequired": false, "context": "ci/example: preflight_check", "state": "ERROR", "targetUrl": "https://ci.example.com/preflight", "detailsUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "BLOCKED",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["ci/example: required_jobs_met", "version_health / assessment"],
                "requiredStatusChecks": [{ "context": "ci/example: required_jobs_met" }, { "context": "version_health / assessment" }]
              }
            }
          }
        }
      }
    }
    """

    private static let missingRequiredContextNotStartedResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "state": "SUCCESS",
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "version_health / assessment", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://github.com/example/version-health", "context": null, "state": null, "targetUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "BLOCKED",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["ci/example: required_jobs_met", "version_health / assessment"],
                "requiredStatusChecks": [{ "context": "ci/example: required_jobs_met" }, { "context": "version_health / assessment" }]
              }
            }
          }
        }
      }
    }
    """

    private static let missingRequiredContextWithRequiredWorkflowProgressResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "state": "PENDING",
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "version_health / assessment", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://github.com/example/version-health", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "dead_code_cleanup", "status": "IN_PROGRESS", "conclusion": null, "isRequired": false, "detailsUrl": "https://ci.example.com/workflows/optional", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "pull_requests", "status": "IN_PROGRESS", "conclusion": null, "isRequired": false, "detailsUrl": "https://ci.example.com/workflows/required", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "dead_code_cleanup / approve", "status": "WAITING", "conclusion": null, "isRequired": false, "detailsUrl": "https://ci.example.com/workflows/optional/approve", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "isRequired": false, "context": "ci/example: generate_beta_build", "state": "PENDING", "targetUrl": "https://ci.example.com/jobs/generate_beta_build", "detailsUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "isRequired": false, "context": "ci/example: generate_release_build", "state": "PENDING", "targetUrl": "https://ci.example.com/jobs/generate_release_build", "detailsUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "isRequired": false, "context": "ci/example: generate_simulator_debug_build", "state": "PENDING", "targetUrl": "https://ci.example.com/jobs/generate_simulator_debug_build", "detailsUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "isRequired": false, "context": "ci/example: run_unit_tests", "state": "PENDING", "targetUrl": "https://ci.example.com/jobs/run_unit_tests", "detailsUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "isRequired": false, "context": "ci/example: validate_release_build", "state": "PENDING", "targetUrl": "https://ci.example.com/jobs/validate_release_build", "detailsUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "isRequired": false, "context": "ci/example: preflight_check", "state": "SUCCESS", "targetUrl": "https://ci.example.com/jobs/preflight_check", "detailsUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "BLOCKED",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["ci/example: required_jobs_met", "version_health / assessment"],
                "requiredStatusChecks": [{ "context": "ci/example: required_jobs_met" }, { "context": "version_health / assessment" }]
              }
            }
          }
        }
      }
    }
    """

    private static let emptyRollupRequiredContextResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "contexts": { "nodes": [] }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["ci/circleci: required_jobs_met"],
                "requiredStatusChecks": [{ "context": "ci/circleci: required_jobs_met" }]
              }
            }
          }
        }
      }
    }
    """

    private static let otherPRGraphQLResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "number": 42,
            "title": "Track required checks",
            "url": "https://github.com/alice/repo/pull/42",
            "author": { "login": "alice" },
            "updatedAt": "2024-01-01T00:00:00Z",
            "labels": {
              "nodes": [{ "id": "label-1", "name": "ci", "color": "0e8a16" }]
            },
            "isDraft": false,
            "state": "OPEN",
            "headRefName": "feature/required-checks",
            "statusCheckRollup": {
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "required_ci", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://ci.example.com/required", "context": null, "state": null, "targetUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "reviewDecision": "APPROVED",
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["required_ci"],
                "requiredStatusChecks": [{ "context": "required_ci" }]
              }
            }
          }
        }
      }
    }
    """

    private static let otherPRFailedRollupMissingRequiredContextResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "number": 42,
            "title": "Track required checks",
            "url": "https://github.com/alice/repo/pull/42",
            "author": { "login": "alice" },
            "updatedAt": "2024-01-01T00:00:00Z",
            "labels": { "nodes": [] },
            "isDraft": false,
            "state": "OPEN",
            "headRefName": "feature/required-checks",
            "statusCheckRollup": {
              "state": "FAILURE",
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "version_health / assessment", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://github.com/example/version-health", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "isRequired": false, "context": "ci/example: preflight_check", "state": "FAILURE", "targetUrl": "https://ci.example.com/preflight", "detailsUrl": null },
                  { "__typename": "CheckRun", "name": "optional_cleanup", "status": "IN_PROGRESS", "conclusion": null, "isRequired": false, "detailsUrl": "https://ci.example.com/optional", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "optional_cleanup / approve", "status": "WAITING", "conclusion": null, "isRequired": false, "detailsUrl": "https://ci.example.com/optional/approve", "context": null, "state": null, "targetUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "BLOCKED",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["ci/example: required_jobs_met", "version_health / assessment"],
                "requiredStatusChecks": [{ "context": "ci/example: required_jobs_met" }, { "context": "version_health / assessment" }]
              }
            }
          }
        }
      }
    }
    """

    @Test func fetchAllOpenPRsUsesBatchGraphQLInsteadOfPerPRView() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.batchStatusResult))
                // --review-requested=@me falls through to default "[]"
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)

        let calls = await mock.executeCalls
        let graphqlCalls = calls.filter { $0.arguments.contains("graphql") }
        let prViewCalls = calls.filter { $0.arguments.contains("pr") && $0.arguments.contains("view") }

        #expect(result.pullRequests.count == 1)
        #expect(!graphqlCalls.isEmpty, "should use gh api graphql for batch status fetch")
        #expect(prViewCalls.isEmpty, "should not use individual gh pr view calls for authored/review PRs")
    }

    @Test func fetchAllOpenPRsResultContainsCorrectHeadRefName() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.batchStatusResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)

        #expect(result.pullRequests.first?.headRefName == "feature/test")
    }

    @Test(arguments: [
        ("FAILURE", BuildStatus.failure),
        ("ERROR", .error),
        ("PENDING", .pending),
        ("EXPECTED", .pending),
        ("SUCCESS", .success),
    ] as [(String, BuildStatus)])
    func fetchAllOpenPRsUsesRollupStateWhenNoCheckMetadata(state: String, expectedStatus: BuildStatus) async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.rollupStateOnlyResult(state: state)))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)

        #expect(result.pullRequests.first?.buildStatus == expectedStatus)
    }

    @Test func fetchAllOpenPRsTreatsOptionalPendingChecksAsSuccessWhenRequiredChecksPass() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.requiredSuccessOptionalPendingResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)

        #expect(result.pullRequests.first?.buildStatus == .success)
    }

    @Test func fetchAllOpenPRsTreatsOptionalFailingChecksAsSuccessWhenRequiredChecksPass() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.requiredSuccessOptionalFailureResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)

        #expect(result.pullRequests.first?.buildStatus == .success)
    }

    @Test func fetchAllOpenPRsFallsBackToBranchProtectionWhenIsRequiredIsMissing() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.branchProtectionRequirednessFallbackResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        let pr = try #require(result.pullRequests.first)
        let requiredCheck = try #require(pr.statusChecks.first { $0.name == "required_ci" })
        let optionalCheck = try #require(pr.statusChecks.first { $0.name == "optional_ci" })

        #expect(pr.buildStatus == .success)
        #expect(requiredCheck.isRequired == true)
        #expect(requiredCheck.isNonBlocking == false)
        #expect(optionalCheck.isRequired == false)
        #expect(optionalCheck.isNonBlocking == true)
        #expect(pr.nonBlockingCheckSummary?.segments.map(\.text) == ["1 pending"])
    }

    @Test func fetchAllOpenPRsKeepsPendingStatusWhenRequiredMetadataIsUnknown() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.missingRequiredMetadataPendingResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)

        #expect(result.pullRequests.first?.buildStatus == .pending)
    }

    @Test func fetchAllOpenPRsTreatsFailedRollupWithMissingRequiredContextAsFailure() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.requiredContextMissingApprovalWaitingResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        let pr = try #require(result.pullRequests.first)

        #expect(pr.buildStatus == .failure)
        #expect(pr.nonBlockingCheckSummary?.segments.map(\.text) == ["1 waiting for approval"])
        let blockingFailures = pr.statusChecks.filter {
            !$0.isNonBlocking && ($0.status == .failure || $0.status == .error)
        }.map(\.name)
        #expect(blockingFailures == ["ci/circleci: preflight_check", "pull_requests"])
        #expect(pr.statusChecks.filter(\.isNonBlocking).map(\.name) == ["dead_code_cleanup / approve"])
    }

    @Test func fetchAllOpenPRsTreatsErrorRollupWithMissingRequiredContextAsError() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.requiredContextMissingErrorResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        let pr = try #require(result.pullRequests.first)
        let blockingFailures = pr.statusChecks.filter {
            !$0.isNonBlocking && ($0.status == .failure || $0.status == .error)
        }.map(\.name)

        #expect(pr.buildStatus == .error)
        #expect(blockingFailures == ["ci/example: preflight_check"])
        #expect(pr.nonBlockingCheckSummary == nil)
    }

    @Test func fetchAllOpenPRsTreatsMissingRequiredContextWithoutStartedCIAsNotStarted() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.missingRequiredContextNotStartedResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        let pr = try #require(result.pullRequests.first)

        #expect(pr.buildStatus == .notStarted)
        #expect(pr.nonBlockingCheckSummary == nil)
    }

    @Test func fetchAllOpenPRsKeepsRequiredWorkflowProgressOutOfNonBlockingSummary() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.missingRequiredContextWithRequiredWorkflowProgressResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        let pr = try #require(result.pullRequests.first)

        #expect(pr.buildStatus == .pending)
        #expect(pr.nonBlockingCheckSummary?.segments.map(\.text) == ["1 waiting for approval"])
        #expect(pr.statusChecks.filter(\.isNonBlocking).map(\.name) == ["dead_code_cleanup / approve"])
    }

    @Test func fetchAllOpenPRsTreatsApprovalNamedStatusContextWithoutGateAsPending() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.optionalApprovalNamedStatusContextResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        let pr = try #require(result.pullRequests.first)

        #expect(pr.buildStatus == .success)
        #expect(pr.nonBlockingCheckSummary?.segments.map(\.text) == ["1 pending"])
    }

    @Test func fetchAllOpenPRsTreatsWaitingCheckRunAsNonBlockingApproval() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.waitingCheckRunApprovalResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        let pr = try #require(result.pullRequests.first)
        let approvalCheck = try #require(pr.statusChecks.first { $0.name == "deploy / wait_for_approval" })

        #expect(pr.buildStatus == .success)
        #expect(approvalCheck.status == .waiting)
        #expect(approvalCheck.isNonBlocking == true)
        #expect(pr.nonBlockingCheckSummary?.segments.map(\.text) == ["1 waiting for approval"])
    }

    @Test func fetchAllOpenPRsTreatsNonRequiredWaitingCheckRunAsNonBlocking() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.requiredSuccessWaitingApprovalParentResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        let pr = try #require(result.pullRequests.first)

        #expect(pr.buildStatus == .success)
        #expect(pr.statusChecks.filter(\.isNonBlocking).map(\.name) == ["deploy"])
        #expect(pr.nonBlockingCheckSummary?.segments.map(\.text) == ["1 waiting for approval"])
    }

    @Test func fetchAllOpenPRsIgnoresWaitingApprovalParentWhenRequiredCIHasNotStarted() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.missingRequiredContextWithWaitingApprovalParentResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        let pr = try #require(result.pullRequests.first)

        #expect(pr.buildStatus == .notStarted)
        #expect(pr.statusChecks.filter(\.isNonBlocking).map(\.name) == ["deploy"])
        #expect(pr.nonBlockingCheckSummary?.segments.map(\.text) == ["1 waiting for approval"])
    }

    @Test func fetchAllOpenPRsDoesNotLetRequiredApprovalGateSuppressOptionalParentCheck() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.requiredApprovalGateDoesNotSuppressOptionalParentResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        let pr = try #require(result.pullRequests.first)

        #expect(pr.buildStatus == .pending)
        #expect(pr.nonBlockingCheckSummary?.segments.map(\.text) == ["1 running"])
    }

    @Test func fetchAllOpenPRsTreatsEmptyRollupWithRequiredContextAsNotStarted() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.emptyRollupRequiredContextResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)

        #expect(result.pullRequests.first?.buildStatus == .notStarted)
    }

    @Test func fetchPRStatusUsesRequiredCIStatusParsing() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("graphql", .success(Self.requiredContextMissingApprovalWaitingResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let status = try await service.fetchPRStatus(
            owner: "alice",
            repo: "repo",
            number: 1,
            updatedAt: Date(),
            enableInactiveDetection: false,
            inactiveThresholdDays: 3
        )

        #expect(status.status == .failure)
        #expect(status.headRefName == "feature/test")
        #expect(status.statusChecks.filter(\.isNonBlocking).map(\.name) == ["dead_code_cleanup / approve"])
    }

    @Test func fetchPRStatusTreatsMissingRequiredContextWithoutStartedCIAsNotStarted() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("graphql", .success(Self.missingRequiredContextNotStartedResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let status = try await service.fetchPRStatus(
            owner: "alice",
            repo: "repo",
            number: 1,
            updatedAt: Date(),
            enableInactiveDetection: false,
            inactiveThresholdDays: 3
        )

        #expect(status.status == .notStarted)
        #expect(status.statusChecks.allSatisfy { !$0.isNonBlocking })
    }

    @Test func fetchOtherPRUsesSingleGraphQLRequest() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("graphql", .success(Self.otherPRGraphQLResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)
        let id = OtherPRIdentifier(host: "github.com", owner: "alice", repo: "repo", number: 42)

        let pr = try #require(await service.fetchOtherPR(id, enableInactiveDetection: false, inactiveThresholdDays: 3))
        let calls = await mock.executeCalls

        #expect(pr.number == 42)
        #expect(pr.title == "Track required checks")
        #expect(pr.headRefName == "feature/required-checks")
        #expect(pr.buildStatus == .success)
        #expect(pr.statusChecks.map(\.name) == ["required_ci"])
        #expect(calls.filter { $0.arguments.contains("graphql") }.count == 1)
        #expect(calls.filter { $0.arguments.contains("pr") && $0.arguments.contains("view") }.isEmpty)
    }

    @Test func fetchOtherPRTreatsFailedRollupWithMissingRequiredContextAsFailure() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("graphql", .success(Self.otherPRFailedRollupMissingRequiredContextResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)
        let id = OtherPRIdentifier(host: "github.com", owner: "alice", repo: "repo", number: 42)

        let pr = try #require(await service.fetchOtherPR(id, enableInactiveDetection: false, inactiveThresholdDays: 3))

        #expect(pr.buildStatus == .failure)
        #expect(pr.nonBlockingCheckSummary?.segments.map(\.text) == ["1 waiting for approval"])
    }

    // MARK: - Comment 1: required WAITING non-approval check must not be hidden

    private static let requiredWaitingNonApprovalCheckResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "state": "PENDING",
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "build", "status": "WAITING", "conclusion": null, "isRequired": true, "detailsUrl": "https://ci.example.com/build", "context": null, "state": null, "targetUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "BLOCKED",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["build", "lint"],
                "requiredStatusChecks": [{ "context": "build" }, { "context": "lint" }]
              }
            }
          }
        }
      }
    }
    """

    @Test func fetchAllOpenPRsDoesNotHideRequiredWaitingNonApprovalCheck() async throws {
        // "build" is required and WAITING (single-component name — not an approval gate).
        // "lint" is required and missing. With the old blanket WAITING guard, "build" was excluded
        // from hasActiveNonApprovalWork, causing the PR to be misclassified as notStarted.
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.requiredWaitingNonApprovalCheckResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        let pr = try #require(result.pullRequests.first)

        // "build" is active required work — PR should be pending, not notStarted.
        #expect(pr.buildStatus == .pending)
    }

    // MARK: - Comment 2: legacy StatusContext approval gate should be non-blocking

    private static let legacyApprovalStatusContextMissingRequiredResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "state": "PENDING",
              "contexts": {
                "nodes": [
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "isRequired": false, "context": "ci/circleci: deploy/approve_deploy", "state": "PENDING", "targetUrl": "https://circleci.com/approve", "detailsUrl": null }
                ]
              }
            },
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "BLOCKED",
            "reviewDecision": null,
            "latestReviews": { "nodes": [] },
            "reviewRequests": { "nodes": [] },
            "baseRef": {
              "branchProtectionRule": {
                "requiredStatusCheckContexts": ["ci/circleci: build"],
                "requiredStatusChecks": [{ "context": "ci/circleci: build" }]
              }
            }
          }
        }
      }
    }
    """

    @Test func fetchAllOpenPRsTreatsLegacyApprovalStatusContextAsNonBlocking() async throws {
        // "ci/circleci: build" is required and missing (notStarted scenario).
        // "ci/circleci: deploy/approve_deploy" is a non-required StatusContext approval gate.
        // It should be excluded from hasActiveNonApprovalWork and marked isNonBlocking, so the
        // overall status is notStarted (not masked as pending by the approval context).
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.legacyApprovalStatusContextMissingRequiredResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        let pr = try #require(result.pullRequests.first)
        let approvalCheck = try #require(pr.statusChecks.first { $0.name == "ci/circleci: deploy/approve_deploy" })

        #expect(pr.buildStatus == .notStarted)
        #expect(approvalCheck.isNonBlocking == true)
    }
}
