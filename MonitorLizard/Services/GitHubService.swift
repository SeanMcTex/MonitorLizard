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
        // Return demo data if in demo mode
        if isDemoMode {
            return PRFetchResult(pullRequests: DemoData.samplePullRequests, isPartial: false)
        }

        // Detect all authenticated GitHub hosts (github.com + any enterprise instances)
        let hosts = try await shellExecutor.getAuthenticatedHosts()

        var allAuthored: [PullRequest] = []
        var allReview: [PullRequest] = []
        var anyPartial = false
        var allFailed = true

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
            }

            if let review = reviewResult.success {
                allReview.append(contentsOf: review)
                allFailed = false
            } else {
                anyPartial = true
            }
        }

        // If all fetches across all hosts failed, throw an error
        if allFailed {
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
        // Fetch all open PRs authored by the current user, excluding archived repositories
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

        // Parse the JSON response
        guard let jsonData = json.data(using: .utf8) else {
            throw GitHubError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try different date formats
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

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string \(dateString)"
            )
        }

        let searchResults = try decoder.decode([GHPRSearchResponse].self, from: jsonData)

        // Convert to PullRequest objects and fetch status for each
        var pullRequests: [PullRequest] = []

        for result in searchResults {
            let updatedAt = try parseDate(result.updatedAt)

            // Fetch detailed PR info with status
            let statusInfo = try await fetchPRStatus(
                owner: extractOwner(from: result.repository.nameWithOwner),
                repo: extractRepo(from: result.repository.nameWithOwner),
                number: result.number,
                updatedAt: updatedAt,
                enableInactiveDetection: enableInactiveDetection,
                inactiveThresholdDays: inactiveThresholdDays,
                host: host
            )

            let pr = PullRequest(
                number: result.number,
                title: result.title,
                repository: PullRequest.RepositoryInfo(
                    name: result.repository.name,
                    nameWithOwner: result.repository.nameWithOwner
                ),
                url: result.url,
                author: PullRequest.Author(login: result.author.login),
                headRefName: statusInfo.headRefName,
                updatedAt: updatedAt,
                buildStatus: statusInfo.status,
                isWatched: false,
                labels: result.labels.map { label in
                    PullRequest.Label(id: label.id, name: label.name, color: label.color)
                },
                type: .authored,
                isDraft: result.isDraft,
                statusChecks: statusInfo.statusChecks,
                reviewDecision: statusInfo.reviewDecision,
                host: host
            )

            pullRequests.append(pr)
        }

        return pullRequests
    }

    private func fetchReviewPRs(enableInactiveDetection: Bool, inactiveThresholdDays: Int, host: String) async throws -> [PullRequest] {
        // Fetch all open PRs where the current user is a requested reviewer, excluding archived repositories
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

        // Parse the JSON response
        guard let jsonData = json.data(using: .utf8) else {
            throw GitHubError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try different date formats
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

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string \(dateString)"
            )
        }

        let searchResults = try decoder.decode([GHPRSearchResponse].self, from: jsonData)

        // Convert to PullRequest objects and fetch status for each
        var pullRequests: [PullRequest] = []

        for result in searchResults {
            let updatedAt = try parseDate(result.updatedAt)

            // Fetch detailed PR info with status
            let statusInfo = try await fetchPRStatus(
                owner: extractOwner(from: result.repository.nameWithOwner),
                repo: extractRepo(from: result.repository.nameWithOwner),
                number: result.number,
                updatedAt: updatedAt,
                enableInactiveDetection: enableInactiveDetection,
                inactiveThresholdDays: inactiveThresholdDays,
                host: host
            )

            let pr = PullRequest(
                number: result.number,
                title: result.title,
                repository: PullRequest.RepositoryInfo(
                    name: result.repository.name,
                    nameWithOwner: result.repository.nameWithOwner
                ),
                url: result.url,
                author: PullRequest.Author(login: result.author.login),
                headRefName: statusInfo.headRefName,
                updatedAt: updatedAt,
                buildStatus: statusInfo.status,
                isWatched: false,
                labels: result.labels.map { label in
                    PullRequest.Label(id: label.id, name: label.name, color: label.color)
                },
                type: .reviewing,
                isDraft: result.isDraft,
                statusChecks: statusInfo.statusChecks,
                reviewDecision: statusInfo.reviewDecision,
                host: host
            )

            pullRequests.append(pr)
        }

        return pullRequests
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
        let allReRequested = !changesRequestedLogins.isEmpty &&
            changesRequestedLogins.allSatisfy { pendingLogins.contains($0) }

        return allReRequested ? .reviewRequired : .changesRequested
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
