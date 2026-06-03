import Testing
import Foundation
@testable import MonitorLizard

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
                  { "__typename": "CheckRun", "name": "deploy", "status": "WAITING", "conclusion": null, "isRequired": false, "detailsUrl": "https://ci.example.com/deploy", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "deploy / approve", "status": "WAITING", "conclusion": null, "isRequired": false, "detailsUrl": "https://ci.example.com/deploy/approve", "context": null, "state": null, "targetUrl": null }
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
        #expect(pr.statusChecks.filter(\.isNonBlocking).map(\.name) == ["deploy / approve"])
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

    // MARK: - Comment 3: non-required non-approval WAITING check must not hide active CI

    private static let nonRequiredWaitingNonApprovalWithMissingRequiredContextResult = """
    {
      "data": {
        "pr0": {
          "pullRequest": {
            "headRefName": "feature/test",
            "statusCheckRollup": {
              "state": "PENDING",
              "contexts": {
                "nodes": [
                  { "__typename": "CheckRun", "name": "version_health / assessment", "status": "COMPLETED", "conclusion": "SUCCESS", "isRequired": true, "detailsUrl": "https://ci.example.com/assessment", "context": null, "state": null, "targetUrl": null },
                  { "__typename": "CheckRun", "name": "build", "status": "WAITING", "conclusion": null, "isRequired": false, "detailsUrl": "https://ci.example.com/build", "context": null, "state": null, "targetUrl": null }
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

    @Test func fetchAllOpenPRsDoesNotHideNonRequiredWaitingNonApprovalCheckWhenRequiredContextMissing() async throws {
        // "ci/example: required_jobs_met" is required and missing.
        // "version_health / assessment" is required and has succeeded.
        // "build" is non-required and WAITING — it is active CI work, not an approval gate.
        // The old blanket WAITING guard incorrectly classified this PR as notStarted.
        // With the narrower looksLikeApprovalGate check, "build" falls through and is
        // counted as active work, so the PR is correctly reported as pending.
        let mock = MockShellExecutor(
            executeResponseMatchers: [
                ("--author=@me", .success(Self.authoredSearchResult)),
                ("graphql", .success(Self.nonRequiredWaitingNonApprovalWithMissingRequiredContextResult))
            ]
        )
        let service = GitHubService(shellExecutor: mock)

        let result = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        let pr = try #require(result.pullRequests.first)
        let buildCheck = try #require(pr.statusChecks.first { $0.name == "build" })

        #expect(pr.buildStatus == .pending)
        // "build" is active CI, not an approval gate, so it must not be classified as a
        // non-blocking "waiting for approval" check.
        #expect(buildCheck.isNonBlocking == false)
        #expect(pr.nonBlockingCheckSummary == nil)
    }
}
