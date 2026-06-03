import Testing
import Foundation
@testable import MonitorLizard

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