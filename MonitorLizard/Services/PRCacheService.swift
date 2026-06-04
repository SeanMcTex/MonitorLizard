import Dependencies
import Foundation

final class PRCacheService: @unchecked Sendable {
    let defaults: UserDefaultsStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var lastMainHash: Int?
    private var lastOtherHash: Int?

    init(defaults: UserDefaultsStore) {
        self.defaults = defaults
    }

    func save(mainPRs: [PullRequest], otherPRs: [PullRequest]) {
        if let data = try? encoder.encode(mainPRs), data.hashValue != lastMainHash {
            defaults.set(data, forKey: PreferenceKeys.cachedMainPRs)
            lastMainHash = data.hashValue
        }
        if let data = try? encoder.encode(otherPRs), data.hashValue != lastOtherHash {
            defaults.set(data, forKey: PreferenceKeys.cachedOtherPRs)
            lastOtherHash = data.hashValue
        }
    }

    func loadMainPRs() -> [PullRequest] { load(forKey: PreferenceKeys.cachedMainPRs) }
    func loadOtherPRs() -> [PullRequest] { load(forKey: PreferenceKeys.cachedOtherPRs) }

    private func load<T: Decodable>(forKey key: PreferenceKeys) -> [T] {
        guard let data = defaults.data(forKey: key),
              let values = try? decoder.decode([T].self, from: data) else { return [] }
        return values
    }
}