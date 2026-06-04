import Dependencies
import Foundation

/// Stores user-provided custom display names for pull requests.
///
/// - Important: This type is `@unchecked Sendable` because all mutable state is accessed
///   exclusively from the main thread. Calling mutating methods from a background thread
///   will trigger an assertion failure in debug builds.
final class CustomNamesService: @unchecked Sendable {
    @Dependency(UserDefaultsStore.self) private var defaults

    init() {}

    func setName(_ name: String, for prID: String) {
        assertMainThread()
        var names = allNames()
        names[prID] = name
        save(names)
    }

    func removeName(for prID: String) {
        assertMainThread()
        var names = allNames()
        names.removeValue(forKey: prID)
        save(names)
    }

    func name(for prID: String) -> String? {
        assertMainThread()
        return allNames()[prID]
    }

    func allNames() -> [String: String] {
        assertMainThread()
        guard let data = defaults.data(forKey: PreferenceKeys.customPRNames),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    func pruneStale(keeping activeIDs: Set<String>) {
        assertMainThread()
        let pruned = allNames().filter { activeIDs.contains($0.key) }
        save(pruned)
    }

    private func save(_ names: [String: String]) {
        if let data = try? JSONEncoder().encode(names) {
            defaults.set(data, forKey: PreferenceKeys.customPRNames)
        }
    }
}
