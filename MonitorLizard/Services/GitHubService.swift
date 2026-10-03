import Combine
import Dependencies
import Foundation

protocol GitHubServicing: Sendable {
    func checkGHAvailable() async throws
    func invalidateHostsCache()
    func fetchAllOpenPRs(enableInactiveDetection: Bool, inactiveThresholdDays: Int, isDemoMode: Bool) async throws -> PRFetchResult
    func fetchPRStatus(owner: String, repo: String, number: Int, updatedAt: Date, enableInactiveDetection: Bool, inactiveThresholdDays: Int, host: String) async throws -> (status: BuildStatus, headRefName: String, statusChecks: [StatusCheck], reviewDecision: ReviewDecision?)
    func fetchOtherPR(_ id: OtherPRIdentifier, enableInactiveDetection: Bool, inactiveThresholdDays: Int) async throws -> PullRequest?

    /// Fetches the open parts of a stack that are not in `knownNumbers`, so a stack
    /// renders as a whole even when only one of its PRs matched the user's searches.
    /// Also reports the stack's merged positions.
    func fetchMissingStackParts(
        stackID: String,
        host: String,
        owner: String,
        repo: String,
        knownNumbers: Set<Int>,
        type: PRType,
        enableInactiveDetection: Bool,
        inactiveThresholdDays: Int
    ) async throws -> StackCompletion
}

/// Result of fetching PRs, including whether the results may be incomplete.
/// When one fetch (authored or review) fails while the other succeeds,
/// `isPartial` is true, signaling that the repo filter should not be reset
/// since the selected repo's PRs may have come from the failed fetch.
struct PRFetchResult {
    let pullRequests: [PullRequest]
    let isPartial: Bool
}

/// Result of completing a partial stack: the open parts that were missing from the
/// user's lists, plus the positions whose pull request has already merged. GitHub
/// keeps merged pull requests in the stack, so those positions are occupied but
/// never show up in searches.
struct StackCompletion {
    let missingParts: [PullRequest]
    let mergedPositions: [Int]

    static let empty = StackCompletion(missingParts: [], mergedPositions: [])
}

/// Service for interacting with GitHub via the `gh` CLI tool
///
/// ## Error Handling Strategy
/// This service distinguishes between three types of errors:
///
/// 1. **Network Errors** (`GitHubError.networkError`):
///    - Occurs when the device has no internet connection
///    - Identified by error messages like "error connecting to api.github.com"
///    - The app preserves cached PR data and shows a network error message
///    - GitHub CLI remains marked as "available" since it's properly installed
///
/// 2. **Authentication Errors** (`GitHubError.notAuthenticated`):
///    - Occurs when GitHub CLI is not authenticated or token is expired
///    - Shows instructions to run `gh auth login`
///    - Marks GitHub CLI as "unavailable" until re-authenticated
///
/// 3. **Installation Errors** (`GitHubError.notInstalled`):
///    - Occurs when GitHub CLI is not installed on the system
///    - Shows installation instructions with link to cli.github.com
///    - Marks GitHub CLI as "unavailable" until installed
///
/// ## Important Notes
/// - `gh auth status` can report misleading errors when offline (says "token is invalid")
/// - Actual API calls like `gh search prs` give proper "error connecting" messages
/// - We skip upfront auth checks at startup and let PR fetches determine the error type
@MainActor
class GitHubService: GitHubServicing, ObservableObject {
    @Dependency(ShellExecutorKey.self) private var shellExecutor
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // Authenticated hosts rarely change (only when adding/removing GitHub accounts).
    // Cache for the session to avoid a redundant `gh auth status` call every 30 s.
    private var cachedHosts: [String]?

    // Hosts whose GraphQL schema predates stack support, detected when the first
    // stack-aware query fails. Kept for the session like `cachedHosts`.
    private var hostsWithoutStackInfo: Set<String> = []

    init() {}

    func checkGHAvailable() async throws {
        let isInstalled = try await shellExecutor.checkGHInstalled()
        guard isInstalled else {
            throw GitHubError.notInstalled
        }

        do {
            let isAuthenticated = try await shellExecutor.checkGHAuthenticated()
            guard isAuthenticated else {
                throw GitHubError.notAuthenticated
            }
        } catch let error as ShellError {
            // Convert ShellError.networkError to GitHubError.networkError
            if case .networkError = error {
                throw GitHubError.networkError
            }
            throw error
        } catch {
            throw error
        }
    }

    private func authenticatedHosts() async throws -> [String] {
        if let cached = cachedHosts {
            return cached
        }
        let hosts = try await shellExecutor.getAuthenticatedHosts()
        cachedHosts = hosts
        return hosts
    }

    /// Call this if the user adds or removes a GitHub account so the next refresh picks up the change.
    func invalidateHostsCache() {
        cachedHosts = nil
    }

    // MARK: - Batch GraphQL

    nonisolated private static let stackEntrySelection = """
    stackEntry {
      position
      stack {
        id
        number
        size
      }
    }
    """

    /// Builds a single `gh api graphql` query that fetches status for all given PRs.
    /// Each PR gets an alias `pr<index>` so the response can be mapped back by position.
    ///
    /// - Parameter includeStackInfo: Pass false for hosts whose schema has no stack
    ///   fields (`PullRequest.stackEntry`); the query is otherwise identical.
    nonisolated static func buildBatchQuery(for requests: [PRStatusRequest], includeStackInfo: Bool = true) -> String {
        guard !requests.isEmpty else { return "query {}" }

        let stackEntry = includeStackInfo ? stackEntrySelection : ""
        let fragments = requests.enumerated().map { index, req in
            """
            pr\(index): repository(owner: "\(req.owner)", name: "\(req.repo)") {
              pullRequest(number: \(req.number)) {
                headRefName
                baseRef {
                  branchProtectionRule {
                    requiredStatusCheckContexts
                    requiredStatusChecks {
                      context
                    }
                  }
                }
                statusCheckRollup {
                  state
                  contexts(last: 100) {
                    nodes {
                      ... on CheckRun {
                        __typename
                        name
                        status
                        conclusion
                        isRequired(pullRequestNumber: \(req.number))
                        detailsUrl
                      }
                      ... on StatusContext {
                        __typename
                        context
                        state
                        isRequired(pullRequestNumber: \(req.number))
                        targetUrl
                      }
                    }
                  }
                }
                mergeable
                mergeStateStatus
                reviewDecision
                latestReviews(last: 20) {
                  nodes {
                    state
                    author { login }
                  }
                }
                latestOpinionatedReviews(last: \(BatchPRStatusResponse.reviewConnectionWindow)) {
                  nodes {
                    state
                    author { login }
                  }
                }
                reviewRequests(last: 20) {
                  nodes {
                    requestedReviewer {
                      ... on User { login }
                    }
                  }
                }
                \(stackEntry)
              }
            }
            """
        }

        return "query {\n\(fragments.joined(separator: "\n"))\nviewer { login }\n}"
    }

    /// Builds a single `gh api graphql` query that fetches the full detail for
    /// one PR, aliased `pr0` so the response maps back like a batch response.
    nonisolated static func buildPRDetailQuery(for request: PRStatusRequest, includeStackInfo: Bool = true) -> String {
        buildBatchDetailQuery(for: [request], includeStackInfo: includeStackInfo)
    }

    /// Builds a single `gh api graphql` query that fetches the full detail for
    /// all given PRs, each aliased `pr<index>` so the response can be mapped
    /// back by position. Used to complete stacks: every open part missing from
    /// the user's lists is fetched in one call instead of one call per part.
    nonisolated static func buildBatchDetailQuery(for requests: [PRStatusRequest], includeStackInfo: Bool = true) -> String {
        guard !requests.isEmpty else { return "query {}" }

        let stackEntry = includeStackInfo ? stackEntrySelection : ""
        let fragments = requests.enumerated().map { index, request in
            """
            pr\(index): repository(owner: "\(request.owner)", name: "\(request.repo)") {
              pullRequest(number: \(request.number)) {
            \(prDetailSelection(for: request))
                \(stackEntry)
              }
            }
            """
        }

        return "query {\n\(fragments.joined(separator: "\n"))\nviewer { login }\n}"
    }

    /// The full per-PR node selection for detail queries: everything needed to
    /// build a `PullRequest` from the response. Shared by the single-PR detail
    /// query and the batch detail query so the two cannot drift apart.
    nonisolated private static func prDetailSelection(for request: PRStatusRequest) -> String {
        """
        number
        title
        url
        author { login }
        updatedAt
        labels(first: 20) {
          nodes {
            id
            name
            color
          }
        }
        isDraft
        state
        headRefName
        baseRef {
          branchProtectionRule {
            requiredStatusCheckContexts
            requiredStatusChecks {
              context
            }
          }
        }
        statusCheckRollup {
          state
          contexts(last: 100) {
            nodes {
              ... on CheckRun {
                __typename
                name
                status
                conclusion
                isRequired(pullRequestNumber: \(request.number))
                detailsUrl
              }
              ... on StatusContext {
                __typename
                context
                state
                isRequired(pullRequestNumber: \(request.number))
                targetUrl
              }
            }
          }
        }
        mergeable
        mergeStateStatus
        reviewDecision
        latestReviews(last: 20) {
          nodes {
            state
            author { login }
          }
        }
        latestOpinionatedReviews(last: \(BatchPRStatusResponse.reviewConnectionWindow)) {
          nodes {
            state
            author { login }
          }
        }
        reviewRequests(last: 20) {
          nodes {
            requestedReviewer {
              ... on User { login }
            }
          }
        }
        """
    }

    /// Builds the query that lists a stack's parts, used to fill in the parts that
    /// are not in the user's own PR lists.
    nonisolated static func buildStackEntriesQuery(stackID: String) -> String {
        """
        query {
          node(id: "\(stackID)") {
            ... on PullRequestStack {
              entries(first: 50) {
                nodes {
                  position
                  pullRequest {
                    number
                    state
                  }
                }
              }
            }
          }
        }
        """
    }

    /// Parses a `gh api graphql` batch response and maps the per-alias results back to
    /// the original `PRStatusRequest` values. PRs whose `pullRequest` field is null
    /// (closed, deleted, or inaccessible) are omitted from the returned dictionary.
    static func parseBatchResponse(
        _ json: String,
        requests: [PRStatusRequest]
    ) throws -> [PRStatusRequest: GHPRDetailResponse] {
        guard let data = json.data(using: .utf8) else {
            throw GitHubError.invalidResponse
        }
        let response = try JSONDecoder().decode(BatchGraphQLResponse.self, from: data)

        var result: [PRStatusRequest: GHPRDetailResponse] = [:]
        for (index, request) in requests.enumerated() {
            if let prNode = response.data["pr\(index)"],
               let prStatus = prNode.pullRequest {
                result[request] = prStatus.toDetailResponse(viewerLogin: response.data.viewerLogin)
            }
        }
        return result
    }

    /// Parses a `gh api graphql` batch detail response into the raw
    /// `BatchPRStatusResponse` per alias plus the authenticated viewer's login.
    /// Unlike `parseBatchResponse`, nothing is flattened to
    /// `GHPRDetailResponse`, so callers can build full `PullRequest` values.
    /// PRs whose `pullRequest` field is null (closed, deleted, or inaccessible)
    /// are omitted from the returned dictionary.
    static func parseBatchDetailResponse(
        _ json: String,
        requests: [PRStatusRequest]
    ) throws -> (responses: [PRStatusRequest: BatchPRStatusResponse], viewerLogin: String?) {
        guard let data = json.data(using: .utf8) else {
            throw GitHubError.invalidResponse
        }
        let response = try JSONDecoder().decode(BatchGraphQLResponse.self, from: data)

        var responses: [PRStatusRequest: BatchPRStatusResponse] = [:]
        for (index, request) in requests.enumerated() {
            if let prNode = response.data["pr\(index)"], let prStatus = prNode.pullRequest {
                responses[request] = prStatus
            }
        }
        return (responses: responses, viewerLogin: response.data.viewerLogin)
    }

    /// Fetches PR status data for all given requests in as few `gh api graphql` calls as
    /// possible, chunking into groups of `Constants.batchQueryChunkSize` to stay within
    /// GitHub's GraphQL complexity limits.
    private func batchFetchStatuses(
        for requests: [PRStatusRequest],
        host: String
    ) async throws -> [PRStatusRequest: GHPRDetailResponse] {
        guard !requests.isEmpty else { return [:] }

        var result: [PRStatusRequest: GHPRDetailResponse] = [:]
        let chunks = stride(from: 0, to: requests.count, by: Constants.batchQueryChunkSize)
            .map { Array(requests[$0..<min($0 + Constants.batchQueryChunkSize, requests.count)]) }

        for chunk in chunks {
            let json = try await executeGraphQL(host: host) { includeStackInfo in
                GitHubService.buildBatchQuery(for: chunk, includeStackInfo: includeStackInfo)
            }
            let chunkResult = try GitHubService.parseBatchResponse(json, requests: chunk)
            result.merge(chunkResult) { _, new in new }
        }

        return result
    }

    /// Runs a GraphQL query, retrying once per host without stack metadata when the
    /// host's schema predates stack support.
    private func executeGraphQL(
        host: String,
        buildQuery: (Bool) -> String
    ) async throws -> String {
        let includeStackInfo = !hostsWithoutStackInfo.contains(host)
        do {
            return try await shellExecutor.execute(
                command: "gh",
                arguments: ["api", "graphql", "-f", "query=\(buildQuery(includeStackInfo))"],
                host: host
            )
        } catch let error as ShellError
            where includeStackInfo && GitHubService.isStackInfoUnsupportedError(error) {
            hostsWithoutStackInfo.insert(host)
            return try await shellExecutor.execute(
                command: "gh",
                arguments: ["api", "graphql", "-f", "query=\(buildQuery(false))"],
                host: host
            )
        }
    }

    /// True when a query failed because the host's schema has no stack fields. The
    /// failure must mention the `stackEntry` field name; GraphQL servers express the
    /// unknown field in a variety of phrasings ("doesn't exist", "cannot query field",
    /// "no such field", and similar), all accepted here so older GitHub Enterprise
    /// hosts fall back to a stack-free query instead of failing to load entirely.
    nonisolated static func isStackInfoUnsupportedError(_ error: Error) -> Bool {
        guard case ShellError.executionFailed(let message) = error else { return false }
        let lowered = message.lowercased()
        guard lowered.contains("stackentry") else { return false }
        return lowered.contains("doesn't exist")
            || lowered.contains("does not exist")
            || lowered.contains("unknown field")
            || lowered.contains("cannot query field")
            || lowered.contains("not defined")
            || lowered.contains("undefined field")
            || lowered.contains("no such field")
            || lowered.contains("unrecognized field")
    }

    // MARK: - Fetch

    func fetchAllOpenPRs(enableInactiveDetection: Bool, inactiveThresholdDays: Int, isDemoMode: Bool = false) async throws -> PRFetchResult {
        // Return demo data if in demo mode
        if isDemoMode {
            return PRFetchResult(pullRequests: DemoData.samplePullRequests, isPartial: false)
        }

        // Detect all authenticated GitHub hosts (github.com + any enterprise instances).
        // Result is cached for the session; call invalidateHostsCache() if accounts change.
        let hosts = try await authenticatedHosts()

        var allAuthored: [PullRequest] = []
        var allReview: [PullRequest] = []
        var anyPartial = false
        var allFailed = true
        var lastError: Error?

        for host in hosts {
            // Fetch both authored and review PRs in parallel with independent error handling
            async let authoredTask = fetchAuthoredPRsSafely(enableInactiveDetection: enableInactiveDetection, inactiveThresholdDays: inactiveThresholdDays, host: host)
            async let reviewTask = fetchReviewPRsSafely(enableInactiveDetection: enableInactiveDetection, inactiveThresholdDays: inactiveThresholdDays, host: host)

            let authoredResult = await authoredTask
            let reviewResult = await reviewTask

            if let authored = authoredResult.success {
                allAuthored.append(contentsOf: authored)
                allFailed = false
            } else {
                anyPartial = true
                lastError = lastError ?? authoredResult.failure
            }

            if let review = reviewResult.success {
                allReview.append(contentsOf: review)
                allFailed = false
            } else {
                anyPartial = true
                lastError = lastError ?? reviewResult.failure
            }
        }

        // If all fetches across all hosts failed, rethrow the actual error so callers
        // can distinguish network failures from auth/other issues.
        if allFailed {
            if let error = lastError {
                if let shellError = error as? ShellError {
                    switch shellError {
                    case .networkError:
                        throw GitHubError.networkError
                    case .commandNotFound:
                        throw GitHubError.notInstalled
                    default:
                        // executionFailed, invalidOutput, etc. — preserve the original error
                        throw error
                    }
                }
                throw error
            }
            throw GitHubError.networkError
        }

        return PRFetchResult(pullRequests: allReview + allAuthored, isPartial: anyPartial)  // Review PRs first to prioritize unblocking teammates
    }

    private func fetchAuthoredPRsSafely(enableInactiveDetection: Bool, inactiveThresholdDays: Int, host: String) async -> Result<[PullRequest], Error> {
        do {
            let prs = try await fetchAuthoredPRs(enableInactiveDetection: enableInactiveDetection, inactiveThresholdDays: inactiveThresholdDays, host: host)
            return .success(prs)
        } catch {
            print("Error fetching authored PRs from \(host): \(error)")
            return .failure(error)
        }
    }

    private func fetchReviewPRsSafely(enableInactiveDetection: Bool, inactiveThresholdDays: Int, host: String) async -> Result<[PullRequest], Error> {
        do {
            let prs = try await fetchReviewPRs(enableInactiveDetection: enableInactiveDetection, inactiveThresholdDays: inactiveThresholdDays, host: host)
            return .success(prs)
        } catch {
            print("Error fetching review PRs from \(host): \(error)")
            return .failure(error)
        }
    }

    private func fetchAuthoredPRs(enableInactiveDetection: Bool, inactiveThresholdDays: Int, host: String) async throws -> [PullRequest] {
        let json = try await shellExecutor.execute(
            command: "gh",
            arguments: [
                "search", "prs",
                "--author=@me",
                "--state=open",
                "--archived=false",
                "--json", "number,title,repository,url,author,updatedAt,labels,isDraft",
                "--limit", "100"
            ],
            host: host
        )
        guard let jsonData = json.data(using: .utf8) else { throw GitHubError.invalidResponse }
        let searchResults = try decodeSearchResults(jsonData)
        return try await buildPRs(from: searchResults, type: .authored,
                                  enableInactiveDetection: enableInactiveDetection,
                                  inactiveThresholdDays: inactiveThresholdDays, host: host)
    }

    private func fetchReviewPRs(enableInactiveDetection: Bool, inactiveThresholdDays: Int, host: String) async throws -> [PullRequest] {
        let json = try await shellExecutor.execute(
            command: "gh",
            arguments: [
                "search", "prs",
                "--review-requested=@me",
                "--state=open",
                "--archived=false",
                "--json", "number,title,repository,url,author,updatedAt,labels,isDraft",
                "--limit", "100"
            ],
            host: host
        )
        guard let jsonData = json.data(using: .utf8) else { throw GitHubError.invalidResponse }
        let searchResults = try decodeSearchResults(jsonData)
        return try await buildPRs(from: searchResults, type: .reviewing,
                                  enableInactiveDetection: enableInactiveDetection,
                                  inactiveThresholdDays: inactiveThresholdDays, host: host)
    }

    /// Decodes search results using a custom ISO-8601 date strategy.
    private func decodeSearchResults(_ jsonData: Data) throws -> [GHPRSearchResponse] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatters: [ISO8601DateFormatter] = [
                { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }(),
                { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
            ]
            for formatter in formatters {
                if let date = formatter.date(from: dateString) { return date }
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        return try decoder.decode([GHPRSearchResponse].self, from: jsonData)
    }

    /// Fetches status for all PRs in one batch GraphQL call, then assembles PullRequest objects.
    private func buildPRs(
        from searchResults: [GHPRSearchResponse],
        type prType: PRType,
        enableInactiveDetection: Bool,
        inactiveThresholdDays: Int,
        host: String
    ) async throws -> [PullRequest] {
        let statusRequests = searchResults.map {
            PRStatusRequest(
                owner: extractOwner(from: $0.repository.nameWithOwner),
                repo: extractRepo(from: $0.repository.nameWithOwner),
                number: $0.number
            )
        }
        let statusMap = try await batchFetchStatuses(for: statusRequests, host: host)

        return try searchResults.map { result in
            let updatedAt = try parseDate(result.updatedAt)
            let request = PRStatusRequest(
                owner: extractOwner(from: result.repository.nameWithOwner),
                repo: extractRepo(from: result.repository.nameWithOwner),
                number: result.number
            )
            let detail = statusMap[request]
            return PullRequest(
                number: result.number,
                title: result.title,
                repository: PullRequest.RepositoryInfo(
                    name: result.repository.name,
                    nameWithOwner: result.repository.nameWithOwner
                ),
                url: result.url,
                author: PullRequest.Author(login: result.author.login),
                headRefName: detail?.headRefName ?? "",
                updatedAt: updatedAt,
                buildStatus: parseOverallStatus(
                    from: detail?.statusCheckRollup,
                    statusCheckRollupState: detail?.statusCheckRollupState,
                    mergeable: detail?.mergeable,
                    mergeStateStatus: detail?.mergeStateStatus,
                    requiredStatusCheckContexts: detail?.requiredStatusCheckContexts,
                    updatedAt: updatedAt,
                    enableInactiveDetection: enableInactiveDetection,
                    inactiveThresholdDays: inactiveThresholdDays
                ),
                isWatched: false,
                labels: result.labels.map { PullRequest.Label(id: $0.id, name: $0.name, color: $0.color) },
                type: prType,
                isDraft: result.isDraft,
                statusChecks: parseStatusChecks(
                    from: detail?.statusCheckRollup,
                    statusCheckRollupState: detail?.statusCheckRollupState,
                    requiredStatusCheckContexts: detail?.requiredStatusCheckContexts
                ),
                reviewDecision: GitHubService.resolveReviewDecision(
                    rawValue: detail?.reviewDecision,
                    latestReviews: detail?.latestReviews,
                    reviewRequests: detail?.reviewRequests
                ),
                host: host,
                stack: detail?.stack,
                viewerApproved: detail?.viewerApproved
            )
        }
    }

    func fetchPRStatus(owner: String, repo: String, number: Int, updatedAt: Date, enableInactiveDetection: Bool, inactiveThresholdDays: Int, host: String = "github.com") async throws -> (status: BuildStatus, headRefName: String, statusChecks: [StatusCheck], reviewDecision: ReviewDecision?) {
        let request = PRStatusRequest(owner: owner, repo: repo, number: number)
        guard let detail = try await batchFetchStatuses(for: [request], host: host)[request] else {
            throw GitHubError.invalidResponse
        }

        let statusChecks = parseStatusChecks(
            from: detail.statusCheckRollup,
            statusCheckRollupState: detail.statusCheckRollupState,
            requiredStatusCheckContexts: detail.requiredStatusCheckContexts
        )

        let status = parseOverallStatus(
            from: detail.statusCheckRollup,
            statusCheckRollupState: detail.statusCheckRollupState,
            mergeable: detail.mergeable,
            mergeStateStatus: detail.mergeStateStatus,
            requiredStatusCheckContexts: detail.requiredStatusCheckContexts,
            updatedAt: updatedAt,
            enableInactiveDetection: enableInactiveDetection,
            inactiveThresholdDays: inactiveThresholdDays
        )

        let reviewDecision = Self.resolveReviewDecision(
            rawValue: detail.reviewDecision,
            latestReviews: detail.latestReviews,
            reviewRequests: detail.reviewRequests
        )

        return (status, detail.headRefName, statusChecks, reviewDecision)
    }

    /// Resolves the effective review decision, accounting for re-requested reviews.
    ///
    /// GitHub's `reviewDecision` field stays `CHANGES_REQUESTED` even after an author
    /// re-requests a review. If every reviewer who requested changes has since been
    /// re-requested, the effective state should be `REVIEW_REQUIRED` instead.
    nonisolated static func resolveReviewDecision(
        rawValue: String?,
        latestReviews: [GHPRDetailResponse.Review]?,
        reviewRequests: [GHPRDetailResponse.ReviewRequest]?
    ) -> ReviewDecision? {
        guard let rawValue, rawValue.uppercased() == "CHANGES_REQUESTED" else {
            return ReviewDecision(rawValue: rawValue?.uppercased() ?? "")
        }

        let pendingLogins = Set((reviewRequests ?? []).compactMap { $0.login })
        let changesRequestedLogins = (latestReviews ?? [])
            .filter { $0.state.uppercased() == "CHANGES_REQUESTED" }
            .compactMap { $0.author?.login }

        // If every CHANGES_REQUESTED reviewer has a pending re-review request,
        // the author has addressed the feedback and is awaiting a new review.
        if !changesRequestedLogins.isEmpty {
            let allReRequested = changesRequestedLogins.allSatisfy { pendingLogins.contains($0) }
            return allReRequested ? .reviewRequired : .changesRequested
        }

        // GitHub sometimes returns latestReviews without the CHANGES_REQUESTED entry
        // (e.g., older reviews fall off). If the API says CHANGES_REQUESTED but we can't
        // find who requested changes, fall back to checking whether any re-review is pending.
        if !pendingLogins.isEmpty {
            return .reviewRequired
        }

        return .changesRequested
    }

    private func parseOverallStatus(from checks: [GHPRDetailResponse.StatusCheck]?, statusCheckRollupState: String? = nil, mergeable: String?, mergeStateStatus: String?, requiredStatusCheckContexts: [String]? = nil, updatedAt: Date, enableInactiveDetection: Bool, inactiveThresholdDays: Int) -> BuildStatus {
        // Check for merge conflicts first (highest priority)
        if let mergeable = mergeable?.uppercased(), mergeable == "CONFLICTING" {
            return .conflict
        }

        if let mergeStateStatus = mergeStateStatus?.uppercased(), mergeStateStatus == "DIRTY" {
            return .conflict
        }

        let checks = checks ?? []

        let missingRequiredContexts = missingRequiredStatusCheckContexts(
            in: checks,
            requiredStatusCheckContexts: requiredStatusCheckContexts
        )
        let checksToEvaluate = statusChecksForOverallStatus(checks, requiredStatusCheckContexts: requiredStatusCheckContexts)
        let hasRequiredMetadata = requiredStatusCheckContexts != nil || checks.contains { $0.isRequired != nil }

        // Priority: conflict > failure > error > pending > success
        var hasFailure = false
        var hasError = false
        var hasPending = !missingRequiredContexts.isEmpty
        var hasSuccess = false

        if !hasRequiredMetadata && checksToEvaluate.isEmpty {
            switch statusCheckRollupState?.uppercased() {
            case "FAILURE":
                hasFailure = true
            case "ERROR":
                hasError = true
            case "PENDING", "EXPECTED":
                hasPending = true
            case "SUCCESS":
                hasSuccess = true
            default:
                break
            }
        }

        if !missingRequiredContexts.isEmpty {
            switch statusCheckRollupState?.uppercased() {
            case "FAILURE":
                hasFailure = true
            case "ERROR":
                hasError = true
            default:
                break
            }
        }

        for check in checksToEvaluate {
            // Check conclusion field (for completed checks)
            if let conclusion = check.conclusion?.uppercased() {
                switch conclusion {
                case "FAILURE", "CANCELLED", "TIMED_OUT":
                    hasFailure = true
                case "ACTION_REQUIRED", "STALE", "STARTUP_FAILURE":
                    hasError = true
                case "SUCCESS":
                    hasSuccess = true
                default:
                    break
                }
            }

            // Check state field (for legacy status API)
            if let state = check.state?.uppercased() {
                switch state {
                case "FAILURE", "ERROR":
                    hasFailure = true
                case "PENDING", "EXPECTED":
                    hasPending = true
                case "SUCCESS":
                    hasSuccess = true
                default:
                    break
                }
            }

            // Check status field (for in-progress checks)
            if let status = check.status?.uppercased() {
                switch status {
                case "IN_PROGRESS", "QUEUED", "WAITING", "PENDING":
                    hasPending = true
                case "COMPLETED":
                    // Check conclusion for completed status
                    break
                default:
                    break
                }
            }
        }

        // Return status based on priority
        if hasFailure {
            return .failure
        }
        if hasError {
            return .error
        }

        if !missingRequiredContexts.isEmpty && !hasActiveNonApprovalWork(in: checks, requiredStatusCheckContexts: requiredStatusCheckContexts) {
            return .notStarted
        }

        if hasPending {
            return .pending
        }

        // Priority: failure > error > pending > inactive > success/unknown
        // Check for inactive branch if enabled (overrides success and unknown)
        if enableInactiveDetection {
            let daysSinceUpdate = Date().timeIntervalSince(updatedAt) / Constants.secondsPerDay
            if daysSinceUpdate >= Double(inactiveThresholdDays) {
                return .inactive
            }
        }

        if hasSuccess {
            return .success
        }

        return .success
    }

    private func hasActiveNonApprovalWork(
        in checks: [GHPRDetailResponse.StatusCheck],
        requiredStatusCheckContexts: [String]?
    ) -> Bool {
        let requiredContextSet = requiredStatusCheckContexts.map(Set.init)
        let approvalParentWorkflowNames = approvalParentWorkflowNames(in: checks, requiredContextSet: requiredContextSet)

        return checks.contains { check in
            guard let checkName = check.name ?? check.context else {
                return false
            }

            let isRequired = check.isRequired ?? requiredContextSet.map { $0.contains(checkName) }

            // Skip WAITING CheckRuns and PENDING StatusContexts that name an approval step
            // (heuristic: 2-component name with "approve" in the job component). Plain CI checks
            // like "build" that happen to be non-required and WAITING fall through so they are
            // correctly counted as active work.
            let isWaitingApprovalGate = check.__typename == "CheckRun"
                && check.status?.uppercased() == "WAITING"
                && isRequired == false
                && looksLikeApprovalGate(checkName)
            let isLegacyApprovalContext = check.__typename == "StatusContext"
                && check.state?.uppercased() == "PENDING"
                && isRequired == false
                && looksLikeApprovalGate(checkName)
            if isWaitingApprovalGate || isLegacyApprovalContext {
                return false
            }

            let isWaitingForApprovalParent = check.__typename == "CheckRun"
                && isRequired == false
                && approvalParentWorkflowNames.contains(checkName)

            if let state = check.state?.uppercased(), ["PENDING", "EXPECTED"].contains(state) {
                return true
            }

            if let status = check.status?.uppercased(), ["IN_PROGRESS", "QUEUED", "WAITING", "PENDING"].contains(status), isWaitingForApprovalParent {
                return false
            }

            if let status = check.status?.uppercased(), ["IN_PROGRESS", "QUEUED", "WAITING", "PENDING"].contains(status) {
                return true
            }

            return false
        }
    }

    private func statusChecksForOverallStatus(
        _ checks: [GHPRDetailResponse.StatusCheck],
        requiredStatusCheckContexts: [String]?
    ) -> [GHPRDetailResponse.StatusCheck] {
        let requiredContextSet = requiredStatusCheckContexts.map(Set.init)
        let requiredChecks = checks.filter { check in
            if let isRequired = check.isRequired {
                return isRequired
            }
            guard let requiredContextSet, let checkName = check.name ?? check.context else {
                return false
            }
            return requiredContextSet.contains(checkName)
        }

        if !requiredChecks.isEmpty {
            return requiredChecks
        }

        let hasRequiredMetadata = requiredContextSet != nil || checks.contains { $0.isRequired != nil }
        return hasRequiredMetadata ? [] : checks
    }

    private func approvalParentWorkflowNames(
        in checks: [GHPRDetailResponse.StatusCheck],
        requiredContextSet: Set<String>?
    ) -> Set<String> {
        Set(checks.compactMap { check -> String? in
            guard check.status?.uppercased() == "WAITING",
                  let checkName = check.name ?? check.context,
                  (check.isRequired ?? requiredContextSet.map { $0.contains(checkName) }) == false
            else { return nil }
            let components = workflowPathComponents(checkName)
            guard components.count == 2 else { return nil }
            let workflowName = String(components[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            return workflowName.isEmpty ? nil : workflowName
        })
    }

    private func missingRequiredStatusCheckContexts(
        in checks: [GHPRDetailResponse.StatusCheck],
        requiredStatusCheckContexts: [String]?
    ) -> Set<String> {
        guard let requiredStatusCheckContexts else { return [] }
        let presentNames = Set(checks.compactMap { $0.name ?? $0.context })
        return Set(requiredStatusCheckContexts).subtracting(presentNames)
    }

    private func parseStatusChecks(
        from checks: [GHPRDetailResponse.StatusCheck]?,
        statusCheckRollupState: String? = nil,
        requiredStatusCheckContexts: [String]? = nil
    ) -> [StatusCheck] {
        guard let checks = checks else {
            return []
        }

        let requiredContextSet = requiredStatusCheckContexts.map(Set.init)
        let missingRequiredContexts = missingRequiredStatusCheckContexts(
            in: checks,
            requiredStatusCheckContexts: requiredStatusCheckContexts
        )
        let rollupFailedWithMissingRequiredContext = !missingRequiredContexts.isEmpty
            && ["FAILURE", "ERROR"].contains(statusCheckRollupState?.uppercased())
        let approvalParentWorkflowNames = approvalParentWorkflowNames(in: checks, requiredContextSet: requiredContextSet)

        return checks.compactMap { check in
            // Extract check name from either name (CheckRun) or context (StatusContext)
            guard let checkName = check.name ?? check.context else {
                return nil
            }

            // Map status/state/conclusion to simplified CheckStatus enum
            let checkStatus: CheckStatus
            if let conclusion = check.conclusion?.uppercased() {
                switch conclusion {
                case "FAILURE", "CANCELLED", "TIMED_OUT":
                    checkStatus = .failure
                case "ACTION_REQUIRED", "STALE", "STARTUP_FAILURE":
                    checkStatus = .error
                case "SUCCESS":
                    checkStatus = .success
                case "SKIPPED", "NEUTRAL":
                    checkStatus = .skipped
                default:
                    checkStatus = .pending
                }
            } else if let state = check.state?.uppercased() {
                switch state {
                case "FAILURE", "ERROR":
                    checkStatus = .failure
                case "PENDING", "EXPECTED":
                    checkStatus = .pending
                case "SUCCESS":
                    checkStatus = .success
                default:
                    checkStatus = .pending
                }
            } else if let status = check.status?.uppercased() {
                switch status {
                case "IN_PROGRESS":
                    checkStatus = .running
                case "WAITING":
                    checkStatus = .waiting
                case "QUEUED":
                    checkStatus = .queued
                case "PENDING":
                    checkStatus = .pending
                case "COMPLETED":
                    // If completed but no conclusion, assume success
                    checkStatus = .success
                default:
                    checkStatus = .pending
                }
            } else {
                // No status information available
                checkStatus = .pending
            }

            // Use detailsUrl or targetUrl as the link
            let detailsUrl = check.detailsUrl ?? check.targetUrl

            // Generate stable ID
            let id = "\(check.__typename)-\(checkName)"
            let isRequired = check.isRequired ?? requiredContextSet.map { $0.contains(checkName) }
            let isBlockingFailure = rollupFailedWithMissingRequiredContext
                && isRequired == false
                && (checkStatus == .failure || checkStatus == .error)
            let isWaitingForApprovalParent = check.__typename == "CheckRun"
                && isRequired == false
                && (checkStatus == .running || checkStatus == .waiting)
                && approvalParentWorkflowNames.contains(checkName)
            let isLegacyApprovalContext: Bool = {
                guard check.__typename == "StatusContext",
                      checkStatus == .pending,
                      isRequired == false,
                      workflowPathComponents(checkName).count == 2 else { return false }
                // Heuristic: same "approve" convention as in hasActiveNonApprovalWork above.
                return String(workflowPathComponents(checkName)[1]).lowercased().contains("approve")
            }()
            // Mirror hasActiveNonApprovalWork: only WAITING checks that name an approval step
            // (e.g. "deploy / approve") are excluded. A plain non-required WAITING check like
            // "build" is active CI work, so it stays aggregate work and is not marked non-blocking.
            let isWaitingApprovalGate = check.__typename == "CheckRun"
                && check.status?.uppercased() == "WAITING"
                && isRequired == false
                && looksLikeApprovalGate(checkName)
            let isRequiredAggregateWork = !missingRequiredContexts.isEmpty
                && !isWaitingApprovalGate
                && !isLegacyApprovalContext
            let isNonBlocking = isRequired == false
                && !isBlockingFailure
                && !isWaitingForApprovalParent
                && !isRequiredAggregateWork

            return StatusCheck(
                id: id,
                name: checkName,
                status: checkStatus,
                detailsUrl: detailsUrl,
                isRequired: isRequired,
                isNonBlocking: isNonBlocking
            )
        }
    }

    private func workflowPathComponents(_ checkName: String) -> [Substring] {
        let suffix = checkName.split(separator: ":", maxSplits: 1).last.map(String.init) ?? checkName
        let path = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.split(separator: "/", maxSplits: 1)
    }

    private func looksLikeApprovalGate(_ checkName: String) -> Bool {
        let components = workflowPathComponents(checkName)
        guard components.count == 2 else { return false }
        return String(components[1]).lowercased().contains("approve")
    }

    private func parseDate(_ dateString: String) throws -> Date {
        let formatters: [ISO8601DateFormatter] = [
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }(),
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime]
                return f
            }()
        ]

        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        throw GitHubError.invalidResponse
    }

    /// Parses a GitHub PR URL of the form `https://<host>/<owner>/<repo>/pull/<number>`
    /// and returns a `OtherPRIdentifier`, or `nil` if the URL is not a valid PR URL.
    nonisolated static func parsePRURL(_ urlString: String) -> OtherPRIdentifier? {
        guard let url = URL(string: urlString),
              let host = url.host,
              !host.isEmpty else { return nil }

        let components = url.pathComponents
        // Expected path components: ["", "<owner>", "<repo>", "pull", "<number>"]
        guard components.count == 5,
              components[3] == "pull",
              let number = Int(components[4]) else { return nil }

        let owner = components[1]
        let repo = components[2]
        guard !owner.isEmpty, !repo.isEmpty else { return nil }

        return OtherPRIdentifier(host: host, owner: owner, repo: repo, number: number)
    }

    /// Fetches a single Other PR by its identifier.
    /// Returns `nil` if the PR is closed, merged, or not found (permanently absent).
    /// Throws on transient errors (network, execution failures) so callers can
    /// distinguish "permanently gone" from "temporarily unavailable".
    func fetchOtherPR(_ id: OtherPRIdentifier, enableInactiveDetection: Bool, inactiveThresholdDays: Int) async throws -> PullRequest? {
        let request = PRStatusRequest(owner: id.owner, repo: id.repo, number: id.number)
        guard let detail = try await fetchPRDetail(for: request, host: id.host) else {
            return nil
        }
        return try buildPullRequest(
            from: detail.response,
            viewerLogin: detail.viewerLogin,
            owner: id.owner,
            repo: id.repo,
            type: .other,
            host: id.host,
            enableInactiveDetection: enableInactiveDetection,
            inactiveThresholdDays: inactiveThresholdDays
        )
    }

    /// Fetches the open parts of a stack that are not in `knownNumbers`, so a stack
    /// renders as a whole even when only one of its PRs matched the user's searches.
    /// Also reports which positions have already merged. Parts that are gone, closed,
    /// or no longer in a stack are skipped.
    func fetchMissingStackParts(
        stackID: String,
        host: String,
        owner: String,
        repo: String,
        knownNumbers: Set<Int>,
        type: PRType,
        enableInactiveDetection: Bool,
        inactiveThresholdDays: Int
    ) async throws -> StackCompletion {
        guard !owner.isEmpty, !repo.isEmpty else { return .empty }

        let json = try await executeGraphQL(host: host) { _ in
            GitHubService.buildStackEntriesQuery(stackID: stackID)
        }
        guard let data = json.data(using: .utf8) else {
            throw GitHubError.invalidResponse
        }
        // An unparseable response is a failure: throwing makes the caller retry on
        // the next poll and cache nothing. A nil `node`, by contrast, is a valid
        // answer — the stack no longer exists — and still returns `.empty` below.
        let response: StackEntriesResponse
        do {
            response = try JSONDecoder().decode(StackEntriesResponse.self, from: data)
        } catch {
            throw GitHubError.invalidResponse
        }
        guard let stack = response.data?.node else {
            return .empty
        }

        var mergedPositions: [Int] = []
        var missingNumbers: [Int] = []
        for entry in stack.entries.nodes {
            guard let entryPR = entry.pullRequest else { continue }

            let state = entryPR.state?.uppercased()
            if state == "MERGED" {
                if let position = entry.position {
                    mergedPositions.append(position)
                }
                continue
            }

            guard state == "OPEN", !knownNumbers.contains(entryPR.number) else { continue }
            missingNumbers.append(entryPR.number)
        }

        guard !missingNumbers.isEmpty else {
            return StackCompletion(missingParts: [], mergedPositions: mergedPositions.sorted())
        }

        // Fetch every missing part's full detail in as few calls as possible,
        // chunked like the status batch to stay within GraphQL complexity limits.
        // Ascending PR number keeps the appended parts in a stable order.
        let requests = missingNumbers
            .sorted()
            .map { PRStatusRequest(owner: owner, repo: repo, number: $0) }
        var details: [PRStatusRequest: BatchPRStatusResponse] = [:]
        var viewerLogin: String?
        let chunks = stride(from: 0, to: requests.count, by: Constants.batchQueryChunkSize)
            .map { Array(requests[$0..<min($0 + Constants.batchQueryChunkSize, requests.count)]) }
        for chunk in chunks {
            let detailJSON = try await executeGraphQL(host: host) { includeStackInfo in
                GitHubService.buildBatchDetailQuery(for: chunk, includeStackInfo: includeStackInfo)
            }
            let parsed = try GitHubService.parseBatchDetailResponse(detailJSON, requests: chunk)
            details.merge(parsed.responses) { _, new in new }
            viewerLogin = viewerLogin ?? parsed.viewerLogin
        }

        var parts: [PullRequest] = []
        for request in requests {
            // A part whose node is null (closed, deleted, or inaccessible) or
            // that no longer reports a stack entry is skipped.
            guard let response = details[request],
                  let part = try buildPullRequest(
                      from: response,
                      viewerLogin: viewerLogin,
                      owner: owner,
                      repo: repo,
                      type: type,
                      host: host,
                      enableInactiveDetection: enableInactiveDetection,
                      inactiveThresholdDays: inactiveThresholdDays
                  ),
                  part.stack != nil else { continue }
            parts.append(part)
        }
        return StackCompletion(missingParts: parts, mergedPositions: mergedPositions.sorted())
    }

    /// Builds a PullRequest from a single-PR detail response. Shared by the Other
    /// PRs list and by stack parts fetched to complete a stack.
    private func buildPullRequest(
        from response: BatchPRStatusResponse,
        viewerLogin: String?,
        owner: String,
        repo: String,
        type: PRType,
        host: String,
        enableInactiveDetection: Bool,
        inactiveThresholdDays: Int
    ) throws -> PullRequest? {
        guard response.state?.uppercased() == "OPEN",
              let responseNumber = response.number,
              let title = response.title,
              let url = response.url,
              let author = response.author,
              let updatedAtString = response.updatedAt,
              let isDraft = response.isDraft else {
            return nil
        }

        let updatedAt = try parseDate(updatedAtString)
        let statusCheckRollup = response.statusCheckRollup?.contexts?.nodes
        let statusChecks = parseStatusChecks(
            from: statusCheckRollup,
            statusCheckRollupState: response.statusCheckRollup?.state,
            requiredStatusCheckContexts: response.requiredStatusCheckContexts
        )
        let status = parseOverallStatus(
            from: statusCheckRollup,
            statusCheckRollupState: response.statusCheckRollup?.state,
            mergeable: response.mergeable,
            mergeStateStatus: response.mergeStateStatus,
            requiredStatusCheckContexts: response.requiredStatusCheckContexts,
            updatedAt: updatedAt,
            enableInactiveDetection: enableInactiveDetection,
            inactiveThresholdDays: inactiveThresholdDays
        )
        let reviewDecision = Self.resolveReviewDecision(
            rawValue: response.reviewDecision,
            latestReviews: response.latestReviews?.nodes,
            reviewRequests: response.reviewRequests?.nodes?.map {
                GHPRDetailResponse.ReviewRequest(login: $0.requestedReviewer?.login)
            }
        )

        return PullRequest(
            number: responseNumber,
            title: title,
            repository: PullRequest.RepositoryInfo(
                name: repo,
                nameWithOwner: "\(owner)/\(repo)"
            ),
            url: url,
            author: PullRequest.Author(login: author.login),
            headRefName: response.headRefName,
            updatedAt: updatedAt,
            buildStatus: status,
            isWatched: false,
            labels: (response.labels?.nodes ?? []).map { label in
                PullRequest.Label(id: label.id, name: label.name, color: label.color)
            },
            type: type,
            isDraft: isDraft,
            statusChecks: statusChecks,
            reviewDecision: reviewDecision,
            host: host,
            stack: response.stackEntry?.stackInfo,
            viewerApproved: response.viewerApproved(viewerLogin: viewerLogin)
        )
    }

    private func fetchPRDetail(for request: PRStatusRequest, host: String) async throws -> (response: BatchPRStatusResponse, viewerLogin: String?)? {
        let json = try await executeGraphQL(host: host) { includeStackInfo in
            GitHubService.buildPRDetailQuery(for: request, includeStackInfo: includeStackInfo)
        }

        guard let data = json.data(using: .utf8) else {
            throw GitHubError.invalidResponse
        }
        let response = try JSONDecoder().decode(BatchGraphQLResponse.self, from: data)
        guard let prNode = response.data["pr0"],
              let pullRequest = prNode.pullRequest else {
            return nil
        }
        return (response: pullRequest, viewerLogin: response.data.viewerLogin)
    }

    private func extractOwner(from nameWithOwner: String) -> String {
        let components = nameWithOwner.split(separator: "/")
        return components.first.map(String.init) ?? ""
    }

    private func extractRepo(from nameWithOwner: String) -> String {
        let components = nameWithOwner.split(separator: "/")
        return components.last.map(String.init) ?? ""
    }
}

enum GitHubError: Error {
    case notInstalled
    case notAuthenticated
    case invalidResponse
    case networkError

    var localizedDescription: String {
        switch self {
        case .notInstalled:
            return "GitHub CLI (gh) is not installed. Please install it from https://cli.github.com"
        case .notAuthenticated:
            return "GitHub CLI is not authenticated. Please run 'gh auth login' in Terminal."
        case .invalidResponse:
            return "Received invalid response from GitHub"
        case .networkError:
            return "Network connection unavailable. Please check your internet connection."
        }
    }
}

// Helper extension for Result
private extension Result {
    var success: Success? {
        if case .success(let value) = self {
            return value
        }
        return nil
    }

    var failure: Failure? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }
}
