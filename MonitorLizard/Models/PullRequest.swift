import Foundation

enum ReviewDecision: String, Codable, Hashable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"

    var systemImageName: String {
        switch self {
        case .approved:         return "person.fill.checkmark"
        case .changesRequested: return "person.fill.xmark"
        case .reviewRequired:   return "person.fill.questionmark"
        }
    }

    var helpText: String {
        switch self {
        case .approved:         return "Approved"
        case .changesRequested: return "Changes requested"
        case .reviewRequired:   return "Review required"
        }
    }
}

enum PRType: String, Codable, Hashable {
    case authored    // PRs created by user
    case reviewing   // PRs awaiting user's review
    case other       // PRs added by URL for monitoring teammates' work

    var sectionTitle: String {
        switch self {
        case .reviewing: "Awaiting My Review"
        case .other:     "Other PR"
        case .authored:  "My PR"
        }
    }

    var pluralizes: Bool {
        switch self {
        case .reviewing: false
        case .other, .authored: true
        }
    }

    func displayTitle(count: Int) -> String {
        pluralizes && count != 1 ? sectionTitle + "s" : sectionTitle
    }
}

struct PullRequest: Identifiable, Hashable {
    let number: Int
    let title: String
    let repository: RepositoryInfo
    let url: String
    let author: Author
    let headRefName: String
    let updatedAt: Date
    var buildStatus: BuildStatus
    var isWatched: Bool
    let labels: [Label]
    let type: PRType
    let isDraft: Bool
    let statusChecks: [StatusCheck]
    var reviewDecision: ReviewDecision?
    let host: String  // GitHub host (e.g. "github.com" or enterprise hostname)
    var customName: String?  // nil = use GitHub title

    var displayTitle: String { customName ?? title }

    var id: String {
        "\(repository.nameWithOwner)#\(number)"
    }

    var hasStatusChecks: Bool {
        !statusChecks.isEmpty
    }

    struct RepositoryInfo: Hashable {
        let name: String
        let nameWithOwner: String
    }

    struct Author: Hashable {
        let login: String
    }

    struct Label: Hashable, Identifiable {
        let id: String
        let name: String
        let color: String
    }
}

enum NonBlockingCheckState: Hashable {
    case failed
    case waitingForApproval
    case running
    case queued
    case pending
    case passed
}

struct NonBlockingCheckSummary: Hashable {
    struct Segment: Identifiable, Hashable {
        let state: NonBlockingCheckState
        let count: Int

        var id: NonBlockingCheckState { state }

        var text: String {
            switch state {
            case .failed:
                return count == 1 ? "1 failed" : "\(count) failed"
            case .waitingForApproval:
                return count == 1 ? "1 waiting for approval" : "\(count) waiting for approval"
            case .running:
                return count == 1 ? "1 running" : "\(count) running"
            case .queued:
                return count == 1 ? "1 queued" : "\(count) queued"
            case .pending:
                return count == 1 ? "1 pending" : "\(count) pending"
            case .passed:
                return count == 1 ? "1 passed" : "\(count) passed"
            }
        }
    }

    let segments: [Segment]
}

extension PullRequest {
    var nonBlockingCheckSummary: NonBlockingCheckSummary? {
        let nonBlockingChecks = statusChecks.filter(\.isNonBlocking)
        guard !nonBlockingChecks.isEmpty else { return nil }

        let counts = Dictionary(grouping: nonBlockingChecks, by: nonBlockingCheckState(for:))
            .mapValues(\.count)
        let needsAttention = [
            NonBlockingCheckState.failed,
            .waitingForApproval,
            .running,
            .queued,
            .pending,
        ].contains { (counts[$0] ?? 0) > 0 }
        guard needsAttention else { return nil }

        let segments = [
            NonBlockingCheckState.failed,
            .waitingForApproval,
            .running,
            .queued,
            .pending,
            .passed,
        ].compactMap { state -> NonBlockingCheckSummary.Segment? in
            guard let count = counts[state], count > 0 else { return nil }
            return NonBlockingCheckSummary.Segment(state: state, count: count)
        }

        return NonBlockingCheckSummary(segments: segments)
    }

    private func nonBlockingCheckState(for check: StatusCheck) -> NonBlockingCheckState {
        switch check.status {
        case .failure, .error:
            return .failed
        case .waiting:
            return .waitingForApproval
        case .running:
            return .running
        case .queued:
            return .queued
        case .pending:
            return .pending
        case .success:
            return .passed
        case .skipped:
            return .passed
        }
    }
}

/// Identifies a specific PR for use in batch status requests.
struct PRStatusRequest: Hashable {
    let owner: String
    let repo: String
    let number: Int
}

// Response structures for parsing gh CLI JSON output
struct GHPRSearchResponse: Codable {
    let number: Int
    let title: String
    let repository: Repository
    let url: String
    let author: Author
    let updatedAt: String
    let labels: [Label]
    let isDraft: Bool

    struct Repository: Codable {
        let name: String
        let nameWithOwner: String
    }

    struct Author: Codable {
        let login: String
    }

    struct Label: Codable {
        let id: String
        let name: String
        let color: String
    }
}

/// Combined response for `gh pr view --json number,title,url,author,updatedAt,labels,isDraft,headRefName,statusCheckRollup,mergeable,mergeStateStatus,reviewDecision,latestReviews,reviewRequests,state`
struct GHPRViewResponse: Codable {
    let number: Int
    let title: String
    let url: String
    let author: Author
    let updatedAt: String
    let labels: [Label]
    let isDraft: Bool
    let headRefName: String
    let statusCheckRollup: [GHPRDetailResponse.StatusCheck]?
    let mergeable: String?
    let mergeStateStatus: String?
    let reviewDecision: String?
    let latestReviews: [GHPRDetailResponse.Review]?
    let reviewRequests: [GHPRDetailResponse.ReviewRequest]?
    let state: String

    struct Author: Codable {
        let login: String
    }

    struct Label: Codable {
        let id: String?
        let name: String
        let color: String
    }
}

/// Response structure for a single PR node inside a `gh api graphql` batch query.
/// Unlike GHPRDetailResponse (used with `gh pr view --json`), review connections use
/// `{ nodes: [...] }` format as returned by the raw GraphQL API.
struct BatchPRStatusResponse: Codable {
    let headRefName: String
    let statusCheckRollup: StatusCheckRollupWrapper?
    let mergeable: String?
    let mergeStateStatus: String?
    let reviewDecision: String?
    let latestReviews: ReviewConnection?
    let reviewRequests: ReviewRequestConnection?
    let baseRef: BaseRef?

    /// Wraps the raw GraphQL `statusCheckRollup { contexts { nodes [...] } }` shape.
    struct StatusCheckRollupWrapper: Codable {
        let contexts: Contexts?

        struct Contexts: Codable {
            let nodes: [GHPRDetailResponse.StatusCheck]?
        }
    }

    struct ReviewConnection: Codable {
        let nodes: [GHPRDetailResponse.Review]?
    }

    struct ReviewRequestConnection: Codable {
        let nodes: [Node]?

        struct Node: Codable {
            let requestedReviewer: Reviewer?

            struct Reviewer: Codable {
                let login: String?  // nil for team reviewers
            }
        }
    }

    struct BaseRef: Codable {
        let branchProtectionRule: BranchProtectionRule?
    }

    struct BranchProtectionRule: Codable {
        let requiredStatusCheckContexts: [String]?
        let requiredStatusChecks: [RequiredStatusCheck]?

        struct RequiredStatusCheck: Codable {
            let context: String
        }
    }

    var requiredStatusCheckContexts: [String]? {
        guard let rule = baseRef?.branchProtectionRule else { return nil }
        let contexts = rule.requiredStatusCheckContexts ?? []
        let checkContexts = rule.requiredStatusChecks?.map(\.context) ?? []
        return Array(Set(contexts + checkContexts))
    }

    /// Converts to GHPRDetailResponse so existing status-parsing logic can be reused.
    func toDetailResponse() -> GHPRDetailResponse {
        let flatRequests = reviewRequests?.nodes?.map {
            GHPRDetailResponse.ReviewRequest(login: $0.requestedReviewer?.login)
        }
        return GHPRDetailResponse(
            headRefName: headRefName,
            statusCheckRollup: statusCheckRollup?.contexts?.nodes,
            mergeable: mergeable,
            mergeStateStatus: mergeStateStatus,
            reviewDecision: reviewDecision,
            latestReviews: latestReviews?.nodes,
            reviewRequests: flatRequests,
            requiredStatusCheckContexts: requiredStatusCheckContexts
        )
    }
}

/// Top-level response from `gh api graphql` for a batch status query.
/// `data` is a dictionary keyed by alias (e.g. "pr0", "pr1").
struct BatchGraphQLResponse: Codable {
    let data: [String: RepositoryNode]

    struct RepositoryNode: Codable {
        let pullRequest: BatchPRStatusResponse?
    }
}

struct GHPRDetailResponse: Codable {
    let headRefName: String
    let statusCheckRollup: [StatusCheck]?
    let mergeable: String?
    let mergeStateStatus: String?
    let reviewDecision: String?
    let latestReviews: [Review]?
    let reviewRequests: [ReviewRequest]?
    let requiredStatusCheckContexts: [String]?

    init(
        headRefName: String,
        statusCheckRollup: [StatusCheck]?,
        mergeable: String?,
        mergeStateStatus: String?,
        reviewDecision: String?,
        latestReviews: [Review]?,
        reviewRequests: [ReviewRequest]?,
        requiredStatusCheckContexts: [String]? = nil
    ) {
        self.headRefName = headRefName
        self.statusCheckRollup = statusCheckRollup
        self.mergeable = mergeable
        self.mergeStateStatus = mergeStateStatus
        self.reviewDecision = reviewDecision
        self.latestReviews = latestReviews
        self.reviewRequests = reviewRequests
        self.requiredStatusCheckContexts = requiredStatusCheckContexts
    }

    struct Review: Codable {
        let author: ReviewAuthor?
        let state: String

        struct ReviewAuthor: Codable {
            let login: String
        }
    }

    struct ReviewRequest: Codable {
        let login: String?  // nil for team review requests
    }

    struct StatusCheck: Codable {
        let name: String?
        let context: String?
        let status: String?
        let state: String?
        let conclusion: String?
        let __typename: String
        let detailsUrl: String?
        let targetUrl: String?
        let isRequired: Bool?

        private enum CodingKeys: String, CodingKey {
            case name, context, status, state, conclusion, __typename, detailsUrl, targetUrl, isRequired
        }
    }
}
