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

    @Test func parseBatchResponseExtractsStackEntry() throws {
        let json = """
        {
          "data": {
            "pr0": {
              "pullRequest": {
                "headRefName": "feature/stacked",
                "statusCheckRollup": null,
                "mergeable": null,
                "mergeStateStatus": null,
                "reviewDecision": null,
                "latestReviews": { "nodes": [] },
                "reviewRequests": { "nodes": [] },
                "stackEntry": {
                  "position": 2,
                  "stack": { "id": "ST_stack", "number": 7, "size": 4 }
                }
              }
            }
          }
        }
        """
        let request = PRStatusRequest(owner: "alice", repo: "repo", number: 2)

        let result = try GitHubService.parseBatchResponse(json, requests: [request])

        #expect(result[request]?.stack == PRStackInfo(id: "ST_stack", number: 7, size: 4, position: 2))
    }

    @Test func parseBatchResponseLeavesStackNilWhenPRIsNotStacked() throws {
        let request = PRStatusRequest(owner: "alice", repo: "widgets", number: 42)

        let result = try GitHubService.parseBatchResponse(Self.makeResponse(), requests: [request])

        #expect(result[request]?.stack == nil)
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

    // MARK: - Viewer approval

    /// Builds a batch response with the given top-level `viewer` JSON (the key is
    /// omitted entirely when nil) and a single PR carrying the given review nodes.
    /// When `opinionatedReviewNodes` is nil the `latestOpinionatedReviews` key is
    /// omitted from the PR object entirely.
    private static func makeViewerResponse(
        viewerJSON: String?,
        latestReviewNodes: String = "",
        opinionatedReviewNodes: String? = ""
    ) -> String {
        let viewerSection = viewerJSON.map { "\n      \"viewer\": \($0)," } ?? ""
        let opinionatedSection = opinionatedReviewNodes.map { "\n                \"latestOpinionatedReviews\": { \"nodes\": [\($0)] }," } ?? ""
        return """
        {
          "data": {\(viewerSection)
            "pr0": {
              "pullRequest": {
                "headRefName": "feature/approval",
                "statusCheckRollup": null,
                "mergeable": null,
                "mergeStateStatus": null,
                "reviewDecision": null,
                "latestReviews": { "nodes": [\(latestReviewNodes)] },\(opinionatedSection)
                "reviewRequests": { "nodes": [] }
              }
            }
          }
        }
        """
    }

    @Test func parseBatchResponseDerivesViewerApprovalFromOpinionatedReviews() throws {
        // Regression: `latestReviews` includes comments, so a later COMMENTED entry
        // masks the approval. The viewer's approval must come from
        // `latestOpinionatedReviews` instead.
        let json = Self.makeViewerResponse(
            viewerJSON: "{ \"login\": \"luke\" }",
            latestReviewNodes: "{ \"state\": \"COMMENTED\", \"author\": { \"login\": \"luke\" } }",
            opinionatedReviewNodes: "{ \"state\": \"APPROVED\", \"author\": { \"login\": \"luke\" } }"
        )
        let request = PRStatusRequest(owner: "owner", repo: "repo", number: 1)

        let result = try GitHubService.parseBatchResponse(json, requests: [request])

        #expect(result[request]?.viewerApproved == true)
    }

    @Test func parseBatchResponseTreatsViewerChangesRequestedAsNotApproved() throws {
        let json = Self.makeViewerResponse(
            viewerJSON: "{ \"login\": \"luke\" }",
            opinionatedReviewNodes: "{ \"state\": \"CHANGES_REQUESTED\", \"author\": { \"login\": \"luke\" } }"
        )
        let request = PRStatusRequest(owner: "owner", repo: "repo", number: 1)

        let result = try GitHubService.parseBatchResponse(json, requests: [request])

        #expect(result[request]?.viewerApproved == false)
    }

    @Test func parseBatchResponseTreatsViewerWithoutOpinionatedReviewAsNotApproved() throws {
        let json = Self.makeViewerResponse(
            viewerJSON: "{ \"login\": \"luke\" }",
            opinionatedReviewNodes: "{ \"state\": \"CHANGES_REQUESTED\", \"author\": { \"login\": \"someone-else\" } }"
        )
        let request = PRStatusRequest(owner: "owner", repo: "repo", number: 1)

        let result = try GitHubService.parseBatchResponse(json, requests: [request])

        #expect(result[request]?.viewerApproved == false)
    }

    @Test func parseBatchResponseLeavesViewerApprovalNilWithoutViewerKey() throws {
        let json = Self.makeViewerResponse(
            viewerJSON: nil,
            opinionatedReviewNodes: "{ \"state\": \"APPROVED\", \"author\": { \"login\": \"luke\" } }"
        )
        let request = PRStatusRequest(owner: "owner", repo: "repo", number: 1)

        let result = try GitHubService.parseBatchResponse(json, requests: [request])

        #expect(result[request]?.viewerApproved == nil)
        #expect(result[request]?.headRefName == "feature/approval")
    }

    @Test func parseBatchResponseLeavesViewerApprovalNilWhenViewerIsNull() throws {
        let json = Self.makeViewerResponse(
            viewerJSON: "null",
            opinionatedReviewNodes: "{ \"state\": \"APPROVED\", \"author\": { \"login\": \"luke\" } }"
        )
        let request = PRStatusRequest(owner: "owner", repo: "repo", number: 1)

        let result = try GitHubService.parseBatchResponse(json, requests: [request])

        #expect(result[request]?.viewerApproved == nil)
        #expect(result[request]?.headRefName == "feature/approval")
    }

    @Test func parseBatchResponseLeavesViewerApprovalNilWhenOpinionatedReviewsAreAbsent() throws {
        let json = Self.makeViewerResponse(
            viewerJSON: "{ \"login\": \"luke\" }",
            opinionatedReviewNodes: nil
        )
        let request = PRStatusRequest(owner: "owner", repo: "repo", number: 1)

        let result = try GitHubService.parseBatchResponse(json, requests: [request])

        #expect(result[request]?.viewerApproved == nil)
        #expect(result[request]?.headRefName == "feature/approval")
    }

    @Test func parseBatchResponseDoesNotTreatOtherUsersApprovalAsViewerApproval() throws {
        let json = Self.makeViewerResponse(
            viewerJSON: "{ \"login\": \"luke\" }",
            opinionatedReviewNodes: "{ \"state\": \"APPROVED\", \"author\": { \"login\": \"someone-else\" } }"
        )
        let request = PRStatusRequest(owner: "owner", repo: "repo", number: 1)

        let result = try GitHubService.parseBatchResponse(json, requests: [request])

        #expect(result[request]?.viewerApproved == false)
    }

    // MARK: - Review window truncation

    /// Builds `count` opinionated review nodes from users other than the viewer.
    private static func otherReviewerNodes(_ count: Int) -> String {
        (1...count).map { index in
            "{ \"state\": \"APPROVED\", \"author\": { \"login\": \"reviewer-\(index)\" } }"
        }.joined(separator: ", ")
    }

    @Test func parseBatchResponseReportsNilWhenAFullWindowOmitsTheViewer() throws {
        // `latestOpinionatedReviews(last:)` returns one node per user, newest
        // first, so a full window may be truncated with the viewer's review
        // pushed off the end. Their absence is unknown, not "no approval".
        let window = BatchPRStatusResponse.reviewConnectionWindow
        let json = Self.makeViewerResponse(
            viewerJSON: "{ \"login\": \"luke\" }",
            opinionatedReviewNodes: Self.otherReviewerNodes(window)
        )
        let request = PRStatusRequest(owner: "owner", repo: "repo", number: 1)

        let result = try GitHubService.parseBatchResponse(json, requests: [request])

        #expect(result[request]?.viewerApproved == nil)
    }

    @Test func parseBatchResponseReportsFalseWhenAPartialWindowOmitsTheViewer() throws {
        // Fewer nodes than the requested window means the connection was
        // exhausted, so the viewer truly has no opinionated review.
        let window = BatchPRStatusResponse.reviewConnectionWindow
        let json = Self.makeViewerResponse(
            viewerJSON: "{ \"login\": \"luke\" }",
            opinionatedReviewNodes: Self.otherReviewerNodes(window - 1)
        )
        let request = PRStatusRequest(owner: "owner", repo: "repo", number: 1)

        let result = try GitHubService.parseBatchResponse(json, requests: [request])

        #expect(result[request]?.viewerApproved == false)
    }

    @Test func parseBatchResponseReportsTrueWhenTheViewerIsInsideAFullWindow() throws {
        let window = BatchPRStatusResponse.reviewConnectionWindow
        let nodes = Self.otherReviewerNodes(window - 1)
            + ", { \"state\": \"APPROVED\", \"author\": { \"login\": \"luke\" } }"
        let json = Self.makeViewerResponse(
            viewerJSON: "{ \"login\": \"luke\" }",
            opinionatedReviewNodes: nodes
        )
        let request = PRStatusRequest(owner: "owner", repo: "repo", number: 1)

        let result = try GitHubService.parseBatchResponse(json, requests: [request])

        #expect(result[request]?.viewerApproved == true)
    }

    // MARK: - Batch detail parsing

    @Test func parseBatchDetailResponseKeepsTheFieldsNeededToBuildAPullRequest() throws {
        let json = """
        {
          "data": {
            "viewer": { "login": "luke" },
            "pr0": {
              "pullRequest": {
                "number": 101,
                "title": "Part 101",
                "url": "https://github.com/acme/widget/pull/101",
                "author": { "login": "alice" },
                "updatedAt": "2025-01-01T00:00:00Z",
                "labels": { "nodes": [] },
                "isDraft": true,
                "state": "OPEN",
                "headRefName": "feature/101",
                "statusCheckRollup": { "state": "SUCCESS", "contexts": { "nodes": [] } },
                "mergeable": "MERGEABLE",
                "mergeStateStatus": "CLEAN",
                "reviewDecision": null,
                "latestReviews": { "nodes": [] },
                "latestOpinionatedReviews": { "nodes": [] },
                "reviewRequests": { "nodes": [] },
                "stackEntry": {
                  "position": 1,
                  "stack": { "id": "PRS_stack", "number": 9, "size": 4 }
                }
              }
            },
            "pr1": { "pullRequest": null }
          }
        }
        """
        let req0 = PRStatusRequest(owner: "acme", repo: "widget", number: 101)
        let req1 = PRStatusRequest(owner: "acme", repo: "widget", number: 104)

        let parsed = try GitHubService.parseBatchDetailResponse(json, requests: [req0, req1])

        #expect(parsed.viewerLogin == "luke")
        #expect(parsed.responses[req1] == nil, "a null pullRequest is omitted")
        let response = try #require(parsed.responses[req0])
        #expect(response.number == 101)
        #expect(response.title == "Part 101")
        #expect(response.isDraft == true)
        #expect(response.state == "OPEN")
        #expect(response.stackEntry?.stackInfo == PRStackInfo(id: "PRS_stack", number: 9, size: 4, position: 1))
    }
}
