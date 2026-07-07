import Dependencies
import Foundation

protocol WatchlistServicing: Sendable {
    func watch(_ pr: PullRequest)
    func unwatch(_ pr: PullRequest)
    func isWatched(_ pr: PullRequest) -> Bool
    func checkForCompletions(currentPRs: [PullRequest]) -> [PullRequest]
    func checkForUpdates(currentPRs: [PullRequest]) -> [PullRequest]
    func clearAll()
    func getWatchedStatus(for prId: String) -> WatchlistService.WatchedPRInfo?
}

/// Manages the user's watched PR list.
///
/// - Important: This type is `@unchecked Sendable` because all mutable state is accessed
///   exclusively from the main thread (via `@MainActor` callers in `PRMonitorViewModel`).
///   Calling mutating methods from a background thread will trigger an assertion failure
///   in debug builds and produces undefined behavior in release.
final class WatchlistService: WatchlistServicing, @unchecked Sendable {
    @Dependency(UserDefaultsStore.self) private var defaults

    private var watchedPRs: [String: WatchedPRInfo] = [:]

    struct WatchedPRInfo: Sendable {
        let lastStatus: BuildStatus
        let timestamp: Date
        let lastUpdatedAt: Date
    }

    init() {
        load()
    }

    func watch(_ pr: PullRequest) {
        assertMainThread()
        watchedPRs[pr.id] = WatchedPRInfo(
            lastStatus: pr.buildStatus,
            timestamp: Date(),
            lastUpdatedAt: pr.updatedAt
        )
        save()
    }

    func unwatch(_ pr: PullRequest) {
        assertMainThread()
        watchedPRs.removeValue(forKey: pr.id)
        save()
    }

    func isWatched(_ pr: PullRequest) -> Bool {
        assertMainThread()
        return watchedPRs[pr.id] != nil
    }

    func checkForCompletions(currentPRs: [PullRequest]) -> [PullRequest] {
        assertMainThread()
        var completed: [PullRequest] = []

        for pr in currentPRs {
            guard let watched = watchedPRs[pr.id] else { continue }

            let wasIncomplete = watched.lastStatus == .notStarted || watched.lastStatus == .pending || watched.lastStatus == .unknown
            let isNowComplete = pr.buildStatus == .success || pr.buildStatus == .failure || pr.buildStatus == .error

            if wasIncomplete && isNowComplete {
                completed.append(pr)
            }

            if watched.lastStatus != pr.buildStatus {
                watchedPRs[pr.id] = WatchedPRInfo(
                    lastStatus: pr.buildStatus,
                    timestamp: Date(),
                    lastUpdatedAt: pr.updatedAt
                )
            }
        }

        let currentPRIds = Set(currentPRs.map { $0.id })
        let watchedPRIds = Set(watchedPRs.keys)
        let closedPRIds = watchedPRIds.subtracting(currentPRIds)

        for closedId in closedPRIds {
            watchedPRs.removeValue(forKey: closedId)
        }

        save()
        return completed
    }

    /// Check for watched PRs whose updatedAt has changed since last check.
    /// Returns PRs that were updated (new comment, push, review, etc.)
    func checkForUpdates(currentPRs: [PullRequest]) -> [PullRequest] {
        var updated: [PullRequest] = []
        for pr in currentPRs {
            guard let watched = watchedPRs[pr.id] else { continue }
            if pr.updatedAt > watched.lastUpdatedAt {
                updated.append(pr)
                watchedPRs[pr.id] = WatchedPRInfo(
                    lastStatus: watched.lastStatus,
                    timestamp: watched.timestamp,
                    lastUpdatedAt: pr.updatedAt
                )
            }
        }
        return updated
    }

    func getWatchedStatus(for prId: String) -> WatchedPRInfo? {
        assertMainThread()
        return watchedPRs[prId]
    }

    private func save() {
        var dict: [String: [String: Any]] = [:]
        for (key, info) in watchedPRs {
            dict[key] = [
                "status": info.lastStatus.rawValue,
                "timestamp": info.timestamp.timeIntervalSince1970,
                "lastUpdatedAt": info.lastUpdatedAt.timeIntervalSince1970
            ]
        }
        defaults.set(dict, forKey: PreferenceKeys.watchedPRs)
    }

    private func load() {
        if let dict = defaults.dictionary(forKey: PreferenceKeys.watchedPRs) as? [String: [String: Any]] {
            watchedPRs.removeAll()
            for (key, value) in dict {
                if let statusRaw = value["status"] as? String,
                   let status = BuildStatus(rawValue: statusRaw),
                   let timestamp = value["timestamp"] as? TimeInterval {
                    let lastUpdatedAt = (value["lastUpdatedAt"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) } ?? Date(timeIntervalSince1970: timestamp)
                    watchedPRs[key] = WatchedPRInfo(
                        lastStatus: status,
                        timestamp: Date(timeIntervalSince1970: timestamp),
                        lastUpdatedAt: lastUpdatedAt
                    )
                }
            }
        }
    }

    func clearAll() {
        assertMainThread()
        watchedPRs.removeAll()
        save()
    }
}
