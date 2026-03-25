import Foundation
import Combine

/// Result of fetching PRs, including whether the results may be incomplete.
/// When one fetch (authored or review) fails while the other succeeds,
/// `isPartial` is true, signaling that the repo filter should not be reset
/// since the selected repo's PRs may have come from the failed fetch.
struct PRFetchResult {
    let pullRequests: [PullRequest]
    let isPartial: Bool
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
class GitHubService: ObservableObject {
    private let shellExecutor = ShellExecutor()
    private let isDemoMode: Bool
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(isDemoMode: Bool = false) {
        self.isDemoMode = isDemoMode
    }

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

    func fetchAllOpenPRs(enableInactiveDetection: Bool, inactiveThresholdDays: Int, isDemoMode: Bool = false) async throws -> PRFetchResult {
        return try await fetchPRsForUser(
            username: "@me",
            enableInactiveDetection: enableInactiveDetection,
            inactiveThresholdDays: inactiveThresholdDays
        )
    }

    /// Fetches PRs for a specific user. For "@me", fetches both authored and
    /// review-requested PRs. For other usernames, only authored PRs.
    func fetchPRsForUser(
        username: String,
        enableInactiveDetection: Bool,
        inactiveThresholdDays: Int
    ) async throws -> PRFetchResult {
        if isDemoMode {
            return PRFetchResult(pullRequests: DemoData.samplePullRequests, isPartial: false)
        }

        let hosts = try await shellExecutor.getAuthenticatedHosts()

        var allAuthored: [PullRequest] = []
        var allReview: [PullRequest] = []
        var anyPartial = false
        var allFailed = true

        for host in hosts {
            let authoredResult = await fetchAuthoredPRsForUserSafely(
                username: username,
                enableInactiveDetection: enableInactiveDetection,
                inactiveThresholdDays: inactiveThresholdDays,
                host: host
            )

            if let authored = authoredResult.success {
                allAuthored.append(contentsOf: authored)
                allFailed = false
            } else {
                anyPartial = true
            }

            // Review PRs only for @me
            if username == "@me" {
                let reviewResult = await fetchReviewPRsSafely(
                    enableInactiveDetection: enableInactiveDetection,
                    inactiveThresholdDays: inactiveThresholdDays,
                    host: host
                )
                if let review = reviewResult.success {
                    allReview.append(contentsOf: review)
                    allFailed = false
                } else {
                    anyPartial = true
                }
            }
        }

        if allFailed {
            throw GitHubError.networkError
        }

        return PRFetchResult(pullRequests: allReview + allAuthored, isPartial: anyPartial)
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

    private func fetchAuthoredPRsForUserSafely(
        username: String,
        enableInactiveDetection: Bool,
        inactiveThresholdDays: Int,
        host: String
    ) async -> Result<[PullRequest], Error> {
        do {
            let prs = try await fetchAuthoredPRsForUser(
                username: username,
                enableInactiveDetection: enableInactiveDetection,
                inactiveThresholdDays: inactiveThresholdDays,
                host: host
            )
            return .success(prs)
        } catch {
            print("Error fetching authored PRs for \(username) from \(host): \(error)")
            return .failure(error)
        }
    }

    /// Fetches authored PRs for a user via a single GraphQL query.
    /// This replaces the N+1 pattern (1 search + N status fetches) with 1 API call.
    private func fetchAuthoredPRsForUser(
        username: String,
        enableInactiveDetection: Bool,
        inactiveThresholdDays: Int,
        host: String
    ) async throws -> [PullRequest] {
        let query = buildGraphQLQuery(author: username)
        let logger = await RefreshLogger.shared

        let json = try await shellExecutor.execute(
            command: "gh",
            arguments: ["api", "graphql", "-f", "query=\(query)"],
            timeout: 60,
            host: host
        )

        guard let jsonData = json.data(using: .utf8) else {
            throw GitHubError.invalidResponse
        }

        let response = try JSONDecoder().decode(GraphQLSearchResponse.self, from: jsonData)

        if let errors = response.errors, !errors.isEmpty {
            let msg = errors.map(\.message).joined(separator: "; ")
            await logger.log("  \(username)@\(host): GraphQL errors: \(msg)")
            throw GitHubError.invalidResponse
        }

        let nodes = response.data?.search.nodes ?? []
        await logger.log("  \(username)@\(host): GraphQL returned \(nodes.count) PRs (1 API call)")

        return nodes.compactMap { node in
            graphQLNodeToPullRequest(
                node: node, type: .authored, host: host,
                enableInactiveDetection: enableInactiveDetection,
                inactiveThresholdDays: inactiveThresholdDays
            )
        }
    }

    private func buildGraphQLQuery(author: String, reviewRequested: String? = nil) -> String {
        let searchQualifier: String
        if let reviewer = reviewRequested {
            searchQualifier = "review-requested:\(reviewer) is:pr is:open archived:false"
        } else {
            searchQualifier = "author:\(author) is:pr is:open archived:false"
        }

        return """
        {
          search(query: "\(searchQualifier)", type: ISSUE, first: 100) {
            nodes {
              ... on PullRequest {
                number
                title
                url
                isDraft
                headRefName
                updatedAt
                mergeable
                reviewDecision
                author { login }
                repository { name nameWithOwner }
                labels(first: 20) { nodes { id name color } }
                commits(last: 1) {
                  nodes {
                    commit {
                      statusCheckRollup {
                        contexts(first: 100) {
                          nodes {
                            __typename
                            ... on CheckRun {
                              name
                              status
                              conclusion
                              detailsUrl
                            }
                            ... on StatusContext {
                              context
                              state
                              targetUrl
                            }
                          }
                        }
                      }
                    }
                  }
                }
                latestReviews(first: 20) { nodes { author { login } state } }
                reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } } } }
              }
            }
          }
        }
        """
    }

    private func graphQLNodeToPullRequest(
        node: GraphQLPRNode,
        type: PRType,
        host: String,
        enableInactiveDetection: Bool,
        inactiveThresholdDays: Int
    ) -> PullRequest? {
        guard let updatedAt = try? parseDate(node.updatedAt) else { return nil }

        // Convert GraphQL status check contexts to our GHPRDetailResponse.StatusCheck format
        let rawChecks: [GHPRDetailResponse.StatusCheck] = node.commits?.nodes?.first?.commit.statusCheckRollup?.contexts.nodes.map { ctx in
            GHPRDetailResponse.StatusCheck(
                name: ctx.name,
                context: ctx.context,
                status: ctx.status,
                state: ctx.state,
                conclusion: ctx.conclusion,
                __typename: ctx.__typename,
                detailsUrl: ctx.detailsUrl,
                targetUrl: ctx.targetUrl
            )
        } ?? []

        let statusChecks = parseStatusChecks(from: rawChecks.isEmpty ? nil : rawChecks)
        let status = parseOverallStatus(
            from: rawChecks.isEmpty ? nil : rawChecks,
            mergeable: node.mergeable,
            mergeStateStatus: nil,
            updatedAt: updatedAt,
            enableInactiveDetection: enableInactiveDetection,
            inactiveThresholdDays: inactiveThresholdDays
        )

        let latestReviews = node.latestReviews?.nodes?.map {
            GHPRDetailResponse.Review(
                author: $0.author.map { GHPRDetailResponse.Review.ReviewAuthor(login: $0.login) },
                state: $0.state
            )
        }
        let reviewRequests = node.reviewRequests?.nodes?.map {
            GHPRDetailResponse.ReviewRequest(login: $0.requestedReviewer?.login)
        }

        let reviewDecision = Self.resolveReviewDecision(
            rawValue: node.reviewDecision,
            latestReviews: latestReviews,
            reviewRequests: reviewRequests
        )

        return PullRequest(
            number: node.number,
            title: node.title,
            repository: PullRequest.RepositoryInfo(
                name: node.repository.name,
                nameWithOwner: node.repository.nameWithOwner
            ),
            url: node.url,
            author: PullRequest.Author(login: node.author?.login ?? "unknown"),
            headRefName: node.headRefName,
            updatedAt: updatedAt,
            buildStatus: status,
            isWatched: false,
            labels: node.labels?.nodes?.map { PullRequest.Label(id: $0.id, name: $0.name, color: $0.color) } ?? [],
            type: type,
            isDraft: node.isDraft,
            statusChecks: statusChecks,
            reviewDecision: reviewDecision,
            host: host
        )
    }

    /// Fetches review-requested PRs via a single GraphQL query.
    private func fetchReviewPRs(enableInactiveDetection: Bool, inactiveThresholdDays: Int, host: String) async throws -> [PullRequest] {
        let query = buildGraphQLQuery(author: "@me", reviewRequested: "@me")
        let logger = await RefreshLogger.shared

        let json = try await shellExecutor.execute(
            command: "gh",
            arguments: ["api", "graphql", "-f", "query=\(query)"],
            timeout: 60,
            host: host
        )

        guard let jsonData = json.data(using: .utf8) else {
            throw GitHubError.invalidResponse
        }

        let response = try JSONDecoder().decode(GraphQLSearchResponse.self, from: jsonData)

        if let errors = response.errors, !errors.isEmpty {
            let msg = errors.map(\.message).joined(separator: "; ")
            await logger.log("  review@\(host): GraphQL errors: \(msg)")
            throw GitHubError.invalidResponse
        }

        let nodes = response.data?.search.nodes ?? []
        await logger.log("  review@\(host): GraphQL returned \(nodes.count) review PRs (1 API call)")

        return nodes.compactMap { node in
            graphQLNodeToPullRequest(
                node: node, type: .reviewing, host: host,
                enableInactiveDetection: enableInactiveDetection,
                inactiveThresholdDays: inactiveThresholdDays
            )
        }
    }

    func fetchPRStatus(owner: String, repo: String, number: Int, updatedAt: Date, enableInactiveDetection: Bool, inactiveThresholdDays: Int, host: String = "github.com") async throws -> (status: BuildStatus, headRefName: String, statusChecks: [StatusCheck], reviewDecision: ReviewDecision?) {
        let json = try await shellExecutor.execute(
            command: "gh",
            arguments: [
                "pr", "view", "\(number)",
                "--repo", "\(owner)/\(repo)",
                "--json", "headRefName,statusCheckRollup,mergeable,mergeStateStatus,reviewDecision,latestReviews,reviewRequests"
            ],
            host: host
        )

        guard let jsonData = json.data(using: .utf8) else {
            throw GitHubError.invalidResponse
        }

        let decoder = JSONDecoder()
        let detail = try decoder.decode(GHPRDetailResponse.self, from: jsonData)

        let statusChecks = parseStatusChecks(from: detail.statusCheckRollup)

        let status = parseOverallStatus(
            from: detail.statusCheckRollup,
            mergeable: detail.mergeable,
            mergeStateStatus: detail.mergeStateStatus,
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

    private func parseOverallStatus(from checks: [GHPRDetailResponse.StatusCheck]?, mergeable: String?, mergeStateStatus: String?, updatedAt: Date, enableInactiveDetection: Bool, inactiveThresholdDays: Int) -> BuildStatus {
        // Check for merge conflicts first (highest priority)
        if let mergeable = mergeable?.uppercased(), mergeable == "CONFLICTING" {
            return .conflict
        }

        if let mergeStateStatus = mergeStateStatus?.uppercased(), mergeStateStatus == "DIRTY" {
            return .conflict
        }

        guard let checks = checks, !checks.isEmpty else {
            return .success
        }

        // Priority: conflict > failure > error > pending > success
        var hasFailure = false
        var hasError = false
        var hasPending = false
        var hasSuccess = false

        for check in checks {
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

    private func parseStatusChecks(from checks: [GHPRDetailResponse.StatusCheck]?) -> [StatusCheck] {
        guard let checks = checks else {
            return []
        }

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
                case "IN_PROGRESS", "QUEUED", "WAITING", "PENDING":
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

            return StatusCheck(
                id: id,
                name: checkName,
                status: checkStatus,
                detailsUrl: detailsUrl
            )
        }
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
    /// Returns `nil` if the PR is closed/merged, not found, or inaccessible.
    func fetchOtherPR(_ id: OtherPRIdentifier, enableInactiveDetection: Bool, inactiveThresholdDays: Int) async -> PullRequest? {
        do {
            let json = try await shellExecutor.execute(
                command: "gh",
                arguments: [
                    "pr", "view", "\(id.number)",
                    "--repo", "\(id.owner)/\(id.repo)",
                    "--json", "number,title,url,author,updatedAt,labels,isDraft,headRefName,statusCheckRollup,mergeable,mergeStateStatus,reviewDecision,latestReviews,reviewRequests,state"
                ],
                host: id.host
            )

            guard let jsonData = json.data(using: .utf8) else { return nil }

            let decoder = JSONDecoder()
            let response = try decoder.decode(GHPRViewResponse.self, from: jsonData)

            guard response.state.uppercased() == "OPEN" else { return nil }

            let updatedAt = try parseDate(response.updatedAt)
            let statusChecks = parseStatusChecks(from: response.statusCheckRollup)
            let status = parseOverallStatus(
                from: response.statusCheckRollup,
                mergeable: response.mergeable,
                mergeStateStatus: response.mergeStateStatus,
                updatedAt: updatedAt,
                enableInactiveDetection: enableInactiveDetection,
                inactiveThresholdDays: inactiveThresholdDays
            )
            let reviewDecision = Self.resolveReviewDecision(
                rawValue: response.reviewDecision,
                latestReviews: response.latestReviews,
                reviewRequests: response.reviewRequests
            )

            return PullRequest(
                number: response.number,
                title: response.title,
                repository: PullRequest.RepositoryInfo(
                    name: id.repo,
                    nameWithOwner: "\(id.owner)/\(id.repo)"
                ),
                url: response.url,
                author: PullRequest.Author(login: response.author.login),
                headRefName: response.headRefName,
                updatedAt: updatedAt,
                buildStatus: status,
                isWatched: false,
                labels: response.labels.map { label in
                    PullRequest.Label(id: label.id ?? label.name, name: label.name, color: label.color)
                },
                type: .other,
                isDraft: response.isDraft,
                statusChecks: statusChecks,
                reviewDecision: reviewDecision,
                host: id.host
            )
        } catch {
            print("Error fetching Other PR \(id.owner)/\(id.repo)#\(id.number): \(error)")
            return nil
        }
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
}
