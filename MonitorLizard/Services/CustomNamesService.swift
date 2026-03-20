import Foundation

class CustomNamesService {
    private let defaults: UserDefaults
    private let key = "customPRNames"

    init(defaults: UserDefaults = .standard) {
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
        guard let data = defaults.data(forKey: key),
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
            defaults.set(data, forKey: key)
        }
    }
}
