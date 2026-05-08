import Testing
import Foundation
@testable import MonitorLizard

// MARK: - Non-blocking Check Summary Tests

@MainActor
struct NonBlockingCheckSummaryTests {

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

    @Test func summaryIsNilWhenOnlyRequiredChecksExist() {
        let pr = makePR(statusChecks: [
            StatusCheck(id: "required", name: "required", status: .success, detailsUrl: nil, isRequired: true)
        ])

        #expect(pr.nonBlockingCheckSummary == nil)
    }

    @Test func summaryIsNilWhenRequirednessIsUnknown() {
        let pr = makePR(statusChecks: [
            StatusCheck(id: "unknown", name: "unknown", status: .pending, detailsUrl: nil, isRequired: nil)
        ])

        #expect(pr.nonBlockingCheckSummary == nil)
    }

    @Test func summaryIsNilWhenAllNonBlockingChecksPassed() {
        let pr = makePR(statusChecks: [
            StatusCheck(id: "optional", name: "optional", status: .success, detailsUrl: nil, isRequired: false, isNonBlocking: true)
        ])

        #expect(pr.nonBlockingCheckSummary == nil)
    }

    @Test func summaryDescribesWaitingAndRunningNonBlockingChecks() throws {
        let pr = makePR(statusChecks: [
            StatusCheck(id: "approval", name: "approval", status: .waiting, detailsUrl: nil, isRequired: false, isNonBlocking: true),
            StatusCheck(id: "analysis", name: "analysis", status: .running, detailsUrl: nil, isRequired: false, isNonBlocking: true)
        ])

        let summary = try #require(pr.nonBlockingCheckSummary)

        #expect(summary.segments.map(\.text) == ["1 waiting for approval", "1 running"])
    }

    @Test func summaryDescribesFailedAndPassedNonBlockingChecksWhenAttentionIsNeeded() throws {
        let pr = makePR(statusChecks: [
            StatusCheck(id: "optional-failed", name: "optional-failed", status: .failure, detailsUrl: nil, isRequired: false, isNonBlocking: true),
            StatusCheck(id: "optional-passed", name: "optional-passed", status: .success, detailsUrl: nil, isRequired: false, isNonBlocking: true)
        ])

        let summary = try #require(pr.nonBlockingCheckSummary)

        #expect(summary.segments.map(\.text) == ["1 failed", "1 passed"])
    }

    @Test func summaryIgnoresNonRequiredChecksThatAreNotNonBlocking() {
        let pr = makePR(statusChecks: [
            StatusCheck(id: "required-workflow-job", name: "required-workflow-job", status: .running, detailsUrl: nil, isRequired: false)
        ])

        #expect(pr.nonBlockingCheckSummary == nil)
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

    /// A genuine network error from the shell (gh CLI) should map to GitHubError.networkError.
    @Test func shellNetworkErrorBecomesGitHubNetworkError() async {
        let mock = MockShellExecutor(executeResponse: .failure(ShellError.networkError("error connecting to api.github.com")))
        let service = GitHubService(shellExecutor: mock)

        do {
            _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
            Issue.record("Expected an error to be thrown")
        } catch let error as GitHubError {
            #expect(error == .networkError)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    /// A missing gh binary should map to GitHubError.notInstalled.
    @Test func commandNotFoundBecomesGitHubNotInstalled() async {
        let mock = MockShellExecutor(executeResponse: .failure(ShellError.commandNotFound))
        let service = GitHubService(shellExecutor: mock)

        do {
            _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
            Issue.record("Expected an error to be thrown")
        } catch let error as GitHubError {
            #expect(error == .notInstalled)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Batch Query Building Tests

struct GitHubServiceBatchQueryTests {

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
        #expect(query.contains("mergeable"))
        #expect(query.contains("mergeStateStatus"))
        #expect(query.contains("reviewDecision"))
        #expect(query.contains("latestReviews"))
        #expect(query.contains("reviewRequests"))
    }

    @Test func buildBatchQueryIncludesRequiredCheckMetadata() {
        let query = GitHubService.buildBatchQuery(for: [
            PRStatusRequest(owner: "alice", repo: "repo", number: 42)
        ])

        #expect(query.contains("isRequired(pullRequestNumber: 42)"))
        #expect(query.contains("baseRef"))
        #expect(query.contains("branchProtectionRule"))
        #expect(query.contains("requiredStatusCheckContexts"))
        #expect(query.contains("requiredStatusChecks"))
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
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "version_health / assessment", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://github.com/example/version-health", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "dead_code_cleanup", "status": "IN_PROGRESS", "conclusion": null, "isRequired": false, "detailsUrl": "https://app.circleci.com/pipelines/gh/owner/repo/1/workflows/optional", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "pull_requests", "status": "IN_PROGRESS", "conclusion": null, "isRequired": false, "detailsUrl": "https://app.circleci.com/pipelines/gh/owner/repo/1/workflows/required", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "context": "ci/circleci: dead_code_cleanup/approve_dead_code_cleanup", "state": "PENDING", "targetUrl": "https://circleci.com/workflow-run/optional", "detailsUrl": null },
                  { "__typename": "StatusContext", "name": null, "status": null, "conclusion": null, "context": "ci/circleci: run_unit_tests", "state": "PENDING", "targetUrl": "https://circleci.com/gh/owner/repo/100", "detailsUrl": null },
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

    @Test func fetchAllOpenPRsTreatsMissingRequiredContextAsPendingAndSummarizesApprovalGate() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.requiredContextMissingApprovalWaitingResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        let pr = try #require(result.pullRequests.first)

        #expect(pr.buildStatus == .pending)
        #expect(pr.nonBlockingCheckSummary?.segments.map(\.text) == ["1 waiting for approval"])
    }

    @Test func fetchAllOpenPRsTreatsEmptyRollupWithRequiredContextAsPending() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.emptyRollupRequiredContextResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)

        #expect(result.pullRequests.first?.buildStatus == .pending)
    }
}
