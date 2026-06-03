import Dependencies
import Foundation

final class CustomNamesService: @unchecked Sendable {
    private let defaults: UserDefaultsStore

    init(defaults: UserDefaultsStore = .liveValue) {
        self.defaults = defaults
    }

    func setName(_ name: String, for prID: String) {
        var names = allNames()
        names[prID] = name
        save(names)
    }

    func removeName(for prID: String) {
        var names = allNames()
        names.removeValue(forKey: prID)
        save(names)
    }

    func name(for prID: String) -> String? {
        allNames()[prID]
    }

    func allNames() -> [String: String] {
        guard let data = defaults.data(forKey: PreferenceKeys.customPRNames),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    func pruneStale(keeping activeIDs: Set<String>) {
        let pruned = allNames().filter { activeIDs.contains($0.key) }
        save(pruned)
    }

    private func save(_ names: [String: String]) {
        if let data = try? JSONEncoder().encode(names) {
            defaults.set(data, forKey: PreferenceKeys.customPRNames)
        }
    }
}