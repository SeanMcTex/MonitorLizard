import Foundation

final class PRCacheService {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // In-session hash to skip redundant UserDefaults writes.
    // Note: Data.hashValue seed resets per process, so these are not persisted.
    private var lastMainHash: Int?
    private var lastOtherHash: Int?

    private enum Key {
        static let mainPRs = "cachedMainPRs"
        static let otherPRs = "cachedOtherPRs"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(mainPRs: [PullRequest], otherPRs: [PullRequest]) {
        if let data = try? encoder.encode(mainPRs), data.hashValue != lastMainHash {
            defaults.set(data, forKey: Key.mainPRs)
            lastMainHash = data.hashValue
        }
        if let data = try? encoder.encode(otherPRs), data.hashValue != lastOtherHash {
            defaults.set(data, forKey: Key.otherPRs)
            lastOtherHash = data.hashValue
        }
    }

    func loadMainPRs() -> [PullRequest] {
        guard let data = defaults.data(forKey: Key.mainPRs),
              let prs = try? decoder.decode([PullRequest].self, from: data) else { return [] }
        return prs
    }

    func loadOtherPRs() -> [PullRequest] {
        guard let data = defaults.data(forKey: Key.otherPRs),
              let prs = try? decoder.decode([PullRequest].self, from: data) else { return [] }
        return prs
    }
}
