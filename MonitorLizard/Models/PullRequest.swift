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
    let statusCheckRollup: [GHPRDetailResponse.StatusCheck]?
    let mergeable: String?
    let mergeStateStatus: String?
    let reviewDecision: String?
    let latestReviews: ReviewConnection?
    let reviewRequests: ReviewRequestConnection?

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

    /// Converts to GHPRDetailResponse so existing status-parsing logic can be reused.
    func toDetailResponse() -> GHPRDetailResponse {
        let flatRequests = reviewRequests?.nodes?.map {
            GHPRDetailResponse.ReviewRequest(login: $0.requestedReviewer?.login)
        }
        return GHPRDetailResponse(
            headRefName: headRefName,
            statusCheckRollup: statusCheckRollup,
            mergeable: mergeable,
            mergeStateStatus: mergeStateStatus,
            reviewDecision: reviewDecision,
            latestReviews: latestReviews?.nodes,
            reviewRequests: flatRequests
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

        private enum CodingKeys: String, CodingKey {
            case name, context, status, state, conclusion, __typename, detailsUrl, targetUrl
        }
    }
}
