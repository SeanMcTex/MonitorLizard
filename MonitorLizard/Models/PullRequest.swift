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

struct PullRequest: Identifiable, Hashable, Codable {
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
    var stack: PRStackInfo?  // nil = not part of a GitHub stack
    /// Whether the authenticated viewer approved this PR, judged by their latest
    /// opinionated review. true = approved, false = not approved (their latest
    /// opinionated review says otherwise, or they have none and the returned
    /// review nodes prove the connection was exhausted), nil = unknown (older
    /// cached data, no viewer login, an absent review connection, or a full
    /// review window that may be truncated before the viewer's review).
    var viewerApproved: Bool? = nil

    var displayTitle: String { customName ?? title }

    /// True only when the viewer's approval is known and positive.
    var isApprovedByViewer: Bool { viewerApproved == true }

    var id: String {
        "\(repository.nameWithOwner)#\(number)"
    }

    var hasStatusChecks: Bool {
        !statusChecks.isEmpty
    }

    /// True when something known prevents the PR from being merged: failing or
    /// pending checks, a conflict, no recent activity, or an outstanding review.
    /// Used both to surface PRs that need attention and to find what a stack waits on.
    var isMergeBlocked: Bool {
        mergeBlockReason != nil
    }

    /// Short description of what prevents this PR from merging, or nil when nothing
    /// known blocks it.
    var mergeBlockReason: String? {
        switch reviewDecision {
        case .changesRequested: return "changes requested"
        case .reviewRequired:   return "review required"
        case .approved, nil:    break
        }
        switch buildStatus {
        case .failure:    return "failing checks"
        case .error:      return "check errors"
        case .conflict:   return "merge conflict"
        case .notStarted: return "checks not started"
        case .pending:    return "checks pending"
        case .inactive:   return "inactive"
        case .success, .unknown: return nil
        }
    }

    struct RepositoryInfo: Hashable, Codable {
        let name: String
        let nameWithOwner: String
    }

    struct Author: Hashable, Codable {
        let login: String
    }

    struct Label: Hashable, Identifiable, Codable {
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

/// Response structure for a single PR node inside a `gh api graphql` batch query.
/// Unlike GHPRDetailResponse (used with `gh pr view --json`), review connections use
/// `{ nodes: [...] }` format as returned by the raw GraphQL API.
struct BatchPRStatusResponse: Codable {
    let number: Int?
    let title: String?
    let url: String?
    let author: Author?
    let updatedAt: String?
    let labels: LabelConnection?
    let isDraft: Bool?
    let state: String?
    let headRefName: String
    let statusCheckRollup: StatusCheckRollupWrapper?
    let mergeable: String?
    let mergeStateStatus: String?
    let reviewDecision: String?
    let latestReviews: ReviewConnection?
    let latestOpinionatedReviews: ReviewConnection?
    let reviewRequests: ReviewRequestConnection?
    let baseRef: BaseRef?
    let stackEntry: StackEntry?

    /// Wraps the raw GraphQL `statusCheckRollup { contexts { nodes [...] } }` shape.
    struct StatusCheckRollupWrapper: Codable {
        let state: String?
        let contexts: Contexts?

        struct Contexts: Codable {
            let nodes: [GHPRDetailResponse.StatusCheck]?
        }
    }

    struct Author: Codable {
        let login: String
    }

    struct LabelConnection: Codable {
        let nodes: [Label]?

        struct Label: Codable {
            let id: String
            let name: String
            let color: String
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

    struct StackEntry: Codable {
        let position: Int?
        let stack: Stack?

        struct Stack: Codable {
            let id: String
            let number: Int
            let size: Int
        }

        var stackInfo: PRStackInfo? {
            guard let stack, let position else { return nil }
            return PRStackInfo(
                id: stack.id,
                number: stack.number,
                size: stack.size,
                position: position
            )
        }
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
        return Array(Set(contexts + checkContexts)).sorted()
    }

    /// Converts to GHPRDetailResponse so existing status-parsing logic can be reused.
    /// - Parameter viewerLogin: Login of the authenticated viewer, used to detect
    ///   whether the viewer approved this PR (see `viewerApproved(viewerLogin:)`).
    func toDetailResponse(viewerLogin: String?) -> GHPRDetailResponse {
        let flatRequests = reviewRequests?.nodes?.map {
            GHPRDetailResponse.ReviewRequest(login: $0.requestedReviewer?.login)
        }
        return GHPRDetailResponse(
            headRefName: headRefName,
            statusCheckRollup: statusCheckRollup?.contexts?.nodes,
            statusCheckRollupState: statusCheckRollup?.state,
            mergeable: mergeable,
            mergeStateStatus: mergeStateStatus,
            reviewDecision: reviewDecision,
            latestReviews: latestReviews?.nodes,
            reviewRequests: flatRequests,
            requiredStatusCheckContexts: requiredStatusCheckContexts,
            stack: stackEntry?.stackInfo,
            viewerApproved: viewerApproved(viewerLogin: viewerLogin)
        )
    }

    /// How many nodes the queries request from `latestOpinionatedReviews`,
    /// which returns one node per user. When that many nodes come back, the
    /// window may be truncated, so a viewer absent from it is unknown rather
    /// than proven to have no opinionated review. The query builders
    /// interpolate this same value so the request and its interpretation
    /// cannot drift apart.
    nonisolated static let reviewConnectionWindow = 20

    /// Whether the authenticated viewer approved this PR, judged by their latest
    /// opinionated review (`latestOpinionatedReviews` ignores later comments,
    /// unlike `viewerLatestReview`). true = approved; false = the viewer's
    /// latest opinionated review is not an approval, including when they have
    /// none and the returned nodes prove the connection was exhausted (fewer
    /// than `reviewConnectionWindow` nodes); nil = unknown (no viewer login, an
    /// absent `latestOpinionatedReviews` connection, or a full window that may
    /// be truncated before the viewer's review).
    func viewerApproved(viewerLogin: String?) -> Bool? {
        guard let viewerLogin, let nodes = latestOpinionatedReviews?.nodes else {
            return nil
        }
        guard let viewerState = nodes.first(where: { $0.author?.login == viewerLogin })?.state else {
            // The viewer is absent from the returned nodes. The connection
            // returns one node per user, newest first, so a full window may be
            // truncated with the viewer's review pushed off the end; a partial
            // window means the connection was exhausted and the viewer truly
            // has no opinionated review.
            return nodes.count >= Self.reviewConnectionWindow ? nil : false
        }
        return viewerState.uppercased() == "APPROVED"
    }
}

/// Top-level response from `gh api graphql` for a batch status query.
/// `data` holds one repository per `pr<n>` alias (e.g. "pr0", "pr1") plus the
/// authenticated `viewer`, which is used to detect the viewer's own approval.
struct BatchGraphQLResponse: Codable {
    let data: BatchData

    struct BatchData: Codable {
        /// Login of the authenticated viewer, or nil when the query did not ask
        /// for it or GitHub returned nothing.
        let viewerLogin: String?

        private let repositories: [String: RepositoryNode]

        subscript(alias: String) -> RepositoryNode? {
            repositories[alias]
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            if let viewerKey = DynamicKey(stringValue: "viewer") {
                viewerLogin = (try? container.decode(Viewer.self, forKey: viewerKey))?.login
            } else {
                viewerLogin = nil
            }

            var decodedRepositories: [String: RepositoryNode] = [:]
            for key in container.allKeys where key.stringValue != "viewer" {
                decodedRepositories[key.stringValue] = try container.decode(RepositoryNode.self, forKey: key)
            }
            repositories = decodedRepositories
        }

        struct Viewer: Codable {
            let login: String?
        }

        /// Coding key that accepts any string, so the dynamic `pr<n>` aliases and
        /// the fixed `viewer` key can be read from the same object.
        private struct DynamicKey: CodingKey {
            var stringValue: String

            init?(stringValue: String) { self.stringValue = stringValue }

            var intValue: Int? { nil }

            init?(intValue: Int) { nil }
        }
    }

    struct RepositoryNode: Codable {
        let pullRequest: BatchPRStatusResponse?
    }
}

/// Response of the stack entries query (`node(id:)` on a PullRequestStack).
/// Lists the stack's parts so PRs missing from the user's lists can be added.
struct StackEntriesResponse: Codable {
    let data: DataNode?

    struct DataNode: Codable {
        let node: Stack?
    }

    struct Stack: Codable {
        let entries: Entries

        struct Entries: Codable {
            let nodes: [Entry]
        }

        struct Entry: Codable {
            let position: Int?
            let pullRequest: Part?

            struct Part: Codable {
                let number: Int
                let state: String?
            }
        }
    }
}

struct GHPRDetailResponse: Codable {
    let headRefName: String
    let statusCheckRollup: [StatusCheck]?
    let statusCheckRollupState: String?
    let mergeable: String?
    let mergeStateStatus: String?
    let reviewDecision: String?
    let latestReviews: [Review]?
    let reviewRequests: [ReviewRequest]?
    let requiredStatusCheckContexts: [String]?
    let stack: PRStackInfo?
    let viewerApproved: Bool?

    init(
        headRefName: String,
        statusCheckRollup: [StatusCheck]?,
        statusCheckRollupState: String? = nil,
        mergeable: String?,
        mergeStateStatus: String?,
        reviewDecision: String?,
        latestReviews: [Review]?,
        reviewRequests: [ReviewRequest]?,
        requiredStatusCheckContexts: [String]? = nil,
        stack: PRStackInfo? = nil,
        viewerApproved: Bool? = nil
    ) {
        self.headRefName = headRefName
        self.statusCheckRollup = statusCheckRollup
        self.statusCheckRollupState = statusCheckRollupState
        self.mergeable = mergeable
        self.mergeStateStatus = mergeStateStatus
        self.reviewDecision = reviewDecision
        self.latestReviews = latestReviews
        self.reviewRequests = reviewRequests
        self.requiredStatusCheckContexts = requiredStatusCheckContexts
        self.stack = stack
        self.viewerApproved = viewerApproved
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
