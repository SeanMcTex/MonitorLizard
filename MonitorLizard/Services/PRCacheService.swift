import Foundation

/// Persists per-user PR data to disk so the app can restore state on restart
/// without waiting for a fresh GitHub fetch.
class PRCacheService {
    static let shared = PRCacheService()

    private let defaults: UserDefaults
    private let cacheKey = "prCacheData"
    private let otherPRsKey = "otherPRsCacheData"
    /// Hash of the last written data to skip redundant writes.
    private var lastCacheHash: Int = 0
    private var lastOtherHash: Int = 0

    struct CachedUserData: Codable {
        var rawPRs: [PullRequest]
        var unsortedPRs: [PullRequest]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(perUserCache: [UUID: (raw: [PullRequest], filtered: [PullRequest])], otherPRs: [PullRequest]) {
        let codableCache = perUserCache.reduce(into: [String: CachedUserData]()) { dict, entry in
            dict[entry.key.uuidString] = CachedUserData(rawPRs: entry.value.raw, unsortedPRs: entry.value.filtered)
        }
        if let data = try? JSONEncoder().encode(codableCache) {
            let hash = data.hashValue
            if hash != lastCacheHash {
                lastCacheHash = hash
                defaults.set(data, forKey: cacheKey)
            }
        }
        if let data = try? JSONEncoder().encode(otherPRs) {
            let hash = data.hashValue
            if hash != lastOtherHash {
                lastOtherHash = hash
                defaults.set(data, forKey: otherPRsKey)
            }
        }
    }

    func loadPerUserCache() -> [UUID: CachedUserData] {
        guard let data = defaults.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: CachedUserData].self, from: data) else {
            return [:]
        }
        return decoded.reduce(into: [UUID: CachedUserData]()) { dict, entry in
            if let uuid = UUID(uuidString: entry.key) {
                dict[uuid] = entry.value
            }
        }
    }

    func loadOtherPRs() -> [PullRequest] {
        guard let data = defaults.data(forKey: otherPRsKey),
              let decoded = try? JSONDecoder().decode([PullRequest].self, from: data) else {
            return []
        }
        return decoded
    }
}
