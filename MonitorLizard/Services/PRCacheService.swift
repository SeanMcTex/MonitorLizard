import Dependencies
import Foundation

protocol PRCacheServicing: Sendable {
    func save(mainPRs: [PullRequest], otherPRs: [PullRequest])
    func loadMainPRs() -> [PullRequest]
    func loadOtherPRs() -> [PullRequest]
}

/// Caches PR data to UserDefaults for fast restoration on app launch.
///
/// - Important: This type is `@unchecked Sendable` because all mutable state is accessed
///   exclusively from the main thread. Calling mutating methods from a background thread
///   will trigger an assertion failure in debug builds.
final class PRCacheService: PRCacheServicing, @unchecked Sendable {
    @Dependency(UserDefaultsStore.self) private var defaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var lastMainHash: Int?
    private var lastOtherHash: Int?

    init() {}

    func save(mainPRs: [PullRequest], otherPRs: [PullRequest]) {
        assertMainThread()
        if let data = try? encoder.encode(mainPRs), data.hashValue != lastMainHash {
            defaults.set(data, forKey: PreferenceKeys.cachedMainPRs)
            lastMainHash = data.hashValue
        }
        if let data = try? encoder.encode(otherPRs), data.hashValue != lastOtherHash {
            defaults.set(data, forKey: PreferenceKeys.cachedOtherPRs)
            lastOtherHash = data.hashValue
        }
    }

    func loadMainPRs() -> [PullRequest] {
        assertMainThread()
        return load(forKey: PreferenceKeys.cachedMainPRs)
    }

    func loadOtherPRs() -> [PullRequest] {
        assertMainThread()
        return load(forKey: PreferenceKeys.cachedOtherPRs)
    }

    private func load<T: Decodable>(forKey key: PreferenceKeys) -> [T] {
        guard let data = defaults.data(forKey: key),
              let values = try? decoder.decode([T].self, from: data) else { return [] }
        return values
    }
}
