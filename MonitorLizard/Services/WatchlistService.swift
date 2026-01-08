import Foundation

class WatchlistService {
    static let shared = WatchlistService()

    private let defaults = UserDefaults.standard
    private let watchlistKey = "watchedPRs"

    private var watchedPRs: [String: WatchedPRInfo] = [:]

    struct WatchedPRInfo {
        let lastStatus: BuildStatus
        let timestamp: Date
    }

    private init() {
        load()
    }

    func watch(_ pr: PullRequest) {
        watchedPRs[pr.id] = WatchedPRInfo(
            lastStatus: pr.buildStatus,
            timestamp: Date()
        )
        save()
    }

    func unwatch(_ pr: PullRequest) {
        watchedPRs.removeValue(forKey: pr.id)
        save()
    }

    func isWatched(_ pr: PullRequest) -> Bool {
        watchedPRs[pr.id] != nil
    }

    /// Check for PRs that have completed builds (transitioned from pending to complete)
    /// Returns PRs that completed since last check
    func checkForCompletions(currentPRs: [PullRequest]) -> [PullRequest] {
        var completed: [PullRequest] = []

        for pr in currentPRs {
            guard let watched = watchedPRs[pr.id] else { continue }

            // Check if status changed from pending to any completed state
            let wasIncomplete = watched.lastStatus == .pending || watched.lastStatus == .unknown
            let isNowComplete = pr.buildStatus == .success || pr.buildStatus == .failure || pr.buildStatus == .error

            if wasIncomplete && isNowComplete {
                completed.append(pr)
            }

            // Update stored status if changed
            if watched.lastStatus != pr.buildStatus {
                watchedPRs[pr.id] = WatchedPRInfo(
                    lastStatus: pr.buildStatus,
                    timestamp: Date()
                )
            }
        }

        // Clean up watched PRs that are no longer open
        let currentPRIds = Set(currentPRs.map { $0.id })
        let watchedPRIds = Set(watchedPRs.keys)
        let closedPRIds = watchedPRIds.subtracting(currentPRIds)

        for closedId in closedPRIds {
            watchedPRs.removeValue(forKey: closedId)
        }

        save()
        return completed
    }

    func getWatchedStatus(for prId: String) -> WatchedPRInfo? {
        watchedPRs[prId]
    }

    private func save() {
        // Convert to simple dictionary for storage
        var dict: [String: [String: Any]] = [:]
        for (key, info) in watchedPRs {
            dict[key] = [
                "status": info.lastStatus.rawValue,
                "timestamp": info.timestamp.timeIntervalSince1970
            ]
        }
        defaults.set(dict, forKey: watchlistKey)
    }

    private func load() {
        if let dict = defaults.dictionary(forKey: watchlistKey) as? [String: [String: Any]] {
            watchedPRs.removeAll()
            for (key, value) in dict {
                if let statusRaw = value["status"] as? String,
                   let status = BuildStatus(rawValue: statusRaw),
                   let timestamp = value["timestamp"] as? TimeInterval {
                    watchedPRs[key] = WatchedPRInfo(
                        lastStatus: status,
                        timestamp: Date(timeIntervalSince1970: timestamp)
                    )
                }
            }
        }
    }

    func clearAll() {
        watchedPRs.removeAll()
        save()
    }
}
