import Dependencies
import Testing
import Foundation
@testable import MonitorLizard

@MainActor
struct GitHubServiceFetchOtherPRTests {

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

    @Test func fetchOtherPRUsesSingleGraphQLRequest() async throws {
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("graphql", .success(Self.otherPRGraphQLResult))
            ]
        )
        let service = withDependencies { $0.shellExecutor = mock } operation: { GitHubService() }
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
        let service = withDependencies { $0.shellExecutor = mock } operation: { GitHubService() }
        let id = OtherPRIdentifier(host: "github.com", owner: "alice", repo: "repo", number: 42)

        let pr = try #require(await service.fetchOtherPR(id, enableInactiveDetection: false, inactiveThresholdDays: 3))

        #expect(pr.buildStatus == .failure)
        #expect(pr.nonBlockingCheckSummary?.segments.map(\.text) == ["1 waiting for approval"])
    }

    @Test func fetchOtherPRReturnsNilWhenPRNotFound() async throws {
        let notFoundJSON = """
        {
          "data": {
            "pr0": {
              "pullRequest": null
            }
          }
        }
        """
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("graphql", .success(notFoundJSON))
            ]
        )
        let service = withDependencies { $0.shellExecutor = mock } operation: { GitHubService() }
        let id = OtherPRIdentifier(host: "github.com", owner: "owner", repo: "repo", number: 99)

        let result = try await service.fetchOtherPR(id, enableInactiveDetection: false, inactiveThresholdDays: 3)
        #expect(result == nil)
    }

    @Test func fetchOtherPRReturnsNilWhenPRIsClosed() async throws {
        let closedPRJSON = """
        {
          "data": {
            "pr0": {
              "pullRequest": {
                "number": 42,
                "title": "Closed PR",
                "url": "https://github.com/alice/repo/pull/42",
                "author": { "login": "alice" },
                "updatedAt": "2024-01-01T00:00:00Z",
                "labels": { "nodes": [] },
                "isDraft": false,
                "state": "CLOSED",
                "headRefName": "feature/closed",
                "statusCheckRollup": { "state": "SUCCESS", "contexts": { "nodes": [] } },
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "CLEAN",
                "reviewDecision": null,
                "latestReviews": { "nodes": [] },
                "reviewRequests": { "nodes": [] },
                "baseRef": {
                  "branchProtectionRule": null
                }
              }
            }
          }
        }
        """
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("graphql", .success(closedPRJSON))
            ]
        )
        let service = withDependencies { $0.shellExecutor = mock } operation: { GitHubService() }
        let id = OtherPRIdentifier(host: "github.com", owner: "alice", repo: "repo", number: 42)

        let result = try await service.fetchOtherPR(id, enableInactiveDetection: false, inactiveThresholdDays: 3)
        #expect(result == nil)
    }

    @Test func fetchOtherPRThrowsOnExecutionFailure() async throws {
        let mock = MockShellExecutor(
            executeResponse: .failure(ShellError.executionFailed("gh: Could not resolve to a Repository with the name 'owner/repo'."))
        )
        let service = withDependencies { $0.shellExecutor = mock } operation: { GitHubService() }
        let id = OtherPRIdentifier(host: "github.com", owner: "owner", repo: "repo", number: 2)

        do {
            _ = try await service.fetchOtherPR(id, enableInactiveDetection: false, inactiveThresholdDays: 3)
            Issue.record("Expected executionFailed to be thrown")
        } catch is ShellError {
            // Expected: executionFailed is thrown as a transient error
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func fetchOtherPRThrowsOnNetworkError() async throws {
        let mock = MockShellExecutor(
            executeResponse: .failure(ShellError.networkError("error connecting to api.github.com"))
        )
        let service = withDependencies { $0.shellExecutor = mock } operation: { GitHubService() }
        let id = OtherPRIdentifier(host: "github.com", owner: "owner", repo: "repo", number: 2)

        do {
            _ = try await service.fetchOtherPR(id, enableInactiveDetection: false, inactiveThresholdDays: 3)
            Issue.record("Expected networkError to be thrown")
        } catch is ShellError {
            // Expected: transient error is thrown, not silently swallowed
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func fetchOtherPRThrowsOnInvalidOutput() async throws {
        let mock = MockShellExecutor(
            executeResponse: .failure(ShellError.invalidOutput)
        )
        let service = withDependencies { $0.shellExecutor = mock } operation: { GitHubService() }
        let id = OtherPRIdentifier(host: "github.com", owner: "owner", repo: "repo", number: 2)

        do {
            _ = try await service.fetchOtherPR(id, enableInactiveDetection: false, inactiveThresholdDays: 3)
            Issue.record("Expected invalidOutput to be thrown")
        } catch is ShellError {
            // Expected: transient error is thrown
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
