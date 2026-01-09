import Foundation
import Combine

@MainActor
class GitHubService: ObservableObject {
    private let shellExecutor = ShellExecutor()
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func checkGHAvailable() async throws {
        let isInstalled = try await shellExecutor.checkGHInstalled()
        guard isInstalled else {
            throw GitHubError.notInstalled
        }

        let isAuthenticated = try await shellExecutor.checkGHAuthenticated()
        guard isAuthenticated else {
            throw GitHubError.notAuthenticated
        }
    }

    func fetchAllOpenPRs(enableStaleDetection: Bool, staleThresholdDays: Int) async throws -> [PullRequest] {
        // Fetch all open PRs authored by the current user
        let json = try await shellExecutor.execute(
            command: "gh",
            arguments: [
                "search", "prs",
                "--author=@me",
                "--state=open",
                "--json", "number,title,repository,url,author,updatedAt,labels",
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
                enableStaleDetection: enableStaleDetection,
                staleThresholdDays: staleThresholdDays
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
                }
            )

            pullRequests.append(pr)
        }

        return pullRequests
    }

    func fetchPRStatus(owner: String, repo: String, number: Int, updatedAt: Date, enableStaleDetection: Bool, staleThresholdDays: Int) async throws -> (status: BuildStatus, headRefName: String) {
        let json = try await shellExecutor.execute(
            command: "gh",
            arguments: [
                "pr", "view", "\(number)",
                "--repo", "\(owner)/\(repo)",
                "--json", "headRefName,statusCheckRollup,mergeable,mergeStateStatus"
            ]
        )

        guard let jsonData = json.data(using: .utf8) else {
            throw GitHubError.invalidResponse
        }

        let decoder = JSONDecoder()
        let detail = try decoder.decode(GHPRDetailResponse.self, from: jsonData)

        let status = parseOverallStatus(
            from: detail.statusCheckRollup,
            mergeable: detail.mergeable,
            mergeStateStatus: detail.mergeStateStatus,
            updatedAt: updatedAt,
            enableStaleDetection: enableStaleDetection,
            staleThresholdDays: staleThresholdDays
        )

        return (status, detail.headRefName)
    }

    private func parseOverallStatus(from checks: [GHPRDetailResponse.StatusCheck]?, mergeable: String?, mergeStateStatus: String?, updatedAt: Date, enableStaleDetection: Bool, staleThresholdDays: Int) -> BuildStatus {
        // Check for merge conflicts first (highest priority)
        if let mergeable = mergeable?.uppercased(), mergeable == "CONFLICTING" {
            return .conflict
        }

        if let mergeStateStatus = mergeStateStatus?.uppercased(), mergeStateStatus == "DIRTY" {
            return .conflict
        }

        guard let checks = checks, !checks.isEmpty else {
            return .unknown
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

        // Priority: failure > error > pending > stale > success/unknown
        // Check for stale branch if enabled (overrides success and unknown)
        if enableStaleDetection {
            let daysSinceUpdate = Date().timeIntervalSince(updatedAt) / Constants.secondsPerDay
            if daysSinceUpdate >= Double(staleThresholdDays) {
                return .stale
            }
        }

        if hasSuccess {
            return .success
        }

        return .unknown
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
            return "Network error occurred"
        }
    }
}
