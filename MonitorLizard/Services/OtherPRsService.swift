import Dependencies
import Foundation

struct OtherPRIdentifier: Codable, Equatable, Sendable {
    let host: String
    let owner: String
    let repo: String
    let number: Int
}

final class OtherPRsService: @unchecked Sendable {
    let defaults: UserDefaultsStore

    init(defaults: UserDefaultsStore) {
        self.defaults = defaults
    }

    func add(_ id: OtherPRIdentifier) {
        var current = all()
        guard !current.contains(id) else { return }
        current.append(id)
        save(current)
    }

    func remove(_ id: OtherPRIdentifier) {
        var current = all()
        current.removeAll { $0 == id }
        save(current)
    }

    func all() -> [OtherPRIdentifier] {
        guard let data = defaults.data(forKey: PreferenceKeys.pinnedPRs),
              let ids = try? JSONDecoder().decode([OtherPRIdentifier].self, from: data) else {
            return []
        }
        return ids
    }

    func contains(_ id: OtherPRIdentifier) -> Bool {
        all().contains(id)
    }

    func clearAll() {
        save([])
    }

    private func save(_ ids: [OtherPRIdentifier]) {
        if let data = try? JSONEncoder().encode(ids) {
            defaults.set(data, forKey: PreferenceKeys.pinnedPRs)
        }
    }
}