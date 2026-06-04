import Dependencies
import Foundation

struct OtherPRIdentifier: Codable, Equatable, Sendable {
    let host: String
    let owner: String
    let repo: String
    let number: Int
}

protocol OtherPRsServicing: Sendable {
    func add(_ id: OtherPRIdentifier)
    func remove(_ id: OtherPRIdentifier)
    func all() -> [OtherPRIdentifier]
    func contains(_ id: OtherPRIdentifier) -> Bool
    func clearAll()
}

/// Manages the list of "Other PRs" the user has pinned.
///
/// - Important: This type is `@unchecked Sendable` because all mutable state is accessed
///   exclusively from the main thread. Calling mutating methods from a background thread
///   will trigger an assertion failure in debug builds.
final class OtherPRsService: OtherPRsServicing, @unchecked Sendable {
    @Dependency(UserDefaultsStore.self) private var defaults

    init() {}

    func add(_ id: OtherPRIdentifier) {
        assertMainThread()
        var current = all()
        guard !current.contains(id) else { return }
        current.append(id)
        save(current)
    }

    func remove(_ id: OtherPRIdentifier) {
        assertMainThread()
        var current = all()
        current.removeAll { $0 == id }
        save(current)
    }

    func all() -> [OtherPRIdentifier] {
        assertMainThread()
        guard let data = defaults.data(forKey: PreferenceKeys.pinnedPRs),
              let ids = try? JSONDecoder().decode([OtherPRIdentifier].self, from: data) else {
            return []
        }
        return ids
    }

    func contains(_ id: OtherPRIdentifier) -> Bool {
        assertMainThread()
        return all().contains(id)
    }

    func clearAll() {
        assertMainThread()
        save([])
    }

    private func save(_ ids: [OtherPRIdentifier]) {
        if let data = try? JSONEncoder().encode(ids) {
            defaults.set(data, forKey: PreferenceKeys.pinnedPRs)
        }
    }
}
