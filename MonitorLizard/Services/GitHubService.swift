import Foundation
import Combine

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

    func fetchAllOpenPRs(enableInactiveDetection: Bool, inactiveThresholdDays: Int, isDemoMode: Bool = false) async throws -> [PullRequest] {
        // Return demo data if in demo mode
        if isDemoMode {
            return DemoData.samplePullRequests
        }

        // Fetch both authored and review PRs in parallel with independent error handling
        // This allows one type to fail (e.g., no review PRs) without affecting the other
        async let authoredTask = fetchAuthoredPRsSafely(enableInactiveDetection: enableInactiveDetection, inactiveThresholdDays: inactiveThresholdDays)
        async let reviewTask = fetchReviewPRsSafely(enableInactiveDetection: enableInactiveDetection, inactiveThresholdDays: inactiveThresholdDays)

        let authoredResult = await authoredTask
        let reviewResult = await reviewTask

        // If both fetches failed, throw an error instead of returning empty array
        // This distinguishes between "no PRs found" (success with empty array) and
        // "couldn't fetch PRs" (network/auth error that should be shown to user)
        if case .failure(let authoredError) = authoredResult,
           case .failure(let reviewError) = reviewResult {
            print("Both PR fetches failed - authored: \(authoredError), review: \(reviewError)")
            // Throw the authored error as it's likely the same root cause
            throw authoredError
        }

        // Extract successful results (empty arrays for failures)
        let authored = authoredResult.success ?? []
        let review = reviewResult.success ?? []

        return review + authored  // Review PRs first to prioritize unblocking teammates
    }

    private func fetchAuthoredPRsSafely(enableInactiveDetection: Bool, inactiveThresholdDays: Int) async -> Result<[PullRequest], Error> {
        do {
            let prs = try await fetchAuthoredPRs(enableInactiveDetection: enableInactiveDetection, inactiveThresholdDays: inactiveThresholdDays)
            return .success(prs)
        } catch {
            print("Error fetching authored PRs: \(error)")
            return .failure(error)
        }
    }

    private func fetchReviewPRsSafely(enableInactiveDetection: Bool, inactiveThresholdDays: Int) async -> Result<[PullRequest], Error> {
        do {
            let prs = try await fetchReviewPRs(enableInactiveDetection: enableInactiveDetection, inactiveThresholdDays: inactiveThresholdDays)
            return .success(prs)
        } catch {
            print("Error fetching review PRs: \(error)")
            return .failure(error)
        }
    }

    private func fetchAuthoredPRs(enableInactiveDetection: Bool, inactiveThresholdDays: Int) async throws -> [PullRequest] {
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
            ]
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
                inactiveThresholdDays: inactiveThresholdDays
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
                statusChecks: statusInfo.statusChecks
            )

            pullRequests.append(pr)
        }

        return pullRequests
    }

    private func fetchReviewPRs(enableInactiveDetection: Bool, inactiveThresholdDays: Int) async throws -> [PullRequest] {
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
            ]
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
                inactiveThresholdDays: inactiveThresholdDays
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
                statusChecks: statusInfo.statusChecks
            )

            pullRequests.append(pr)
        }

        return pullRequests
    }

    func fetchPRStatus(owner: String, repo: String, number: Int, updatedAt: Date, enableInactiveDetection: Bool, inactiveThresholdDays: Int) async throws -> (status: BuildStatus, headRefName: String, statusChecks: [StatusCheck]) {
        let json = try await shellExecutor.execute(
            command: "gh",
            arguments: [
                "pr", "view", "\(number)",
                "--repo", "\(owner)/\(repo)",
                "--json", "headRefName,statusCheckRollup,mergeable,mergeStateStatus,reviewDecision"
            ]
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
            reviewDecision: detail.reviewDecision,
            updatedAt: updatedAt,
            enableInactiveDetection: enableInactiveDetection,
            inactiveThresholdDays: inactiveThresholdDays
        )

        return (status, detail.headRefName, statusChecks)
    }

    private func parseOverallStatus(from checks: [GHPRDetailResponse.StatusCheck]?, mergeable: String?, mergeStateStatus: String?, reviewDecision: String?, updatedAt: Date, enableInactiveDetection: Bool, inactiveThresholdDays: Int) -> BuildStatus {
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

        // Check for changes requested (after errors, before pending)
        if let reviewDecision = reviewDecision?.uppercased(), reviewDecision == "CHANGES_REQUESTED" {
            return .changesRequested
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
