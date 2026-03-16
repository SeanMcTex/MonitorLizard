import Foundation

struct PinnedPRIdentifier: Codable, Equatable {
    let host: String
    let owner: String
    let repo: String
    let number: Int
}

class PinnedPRsService {
    private let defaults: UserDefaults
    private let pinnedPRsKey = "pinnedPRs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func add(_ id: PinnedPRIdentifier) {
        var current = all()
        guard !current.contains(id) else { return }
        current.append(id)
        save(current)
    }

    func remove(_ id: PinnedPRIdentifier) {
        var current = all()
        current.removeAll { $0 == id }
        save(current)
    }

    func all() -> [PinnedPRIdentifier] {
        guard let data = defaults.data(forKey: pinnedPRsKey),
              let ids = try? JSONDecoder().decode([PinnedPRIdentifier].self, from: data) else {
            return []
        }
        return ids
    }

    func contains(_ id: PinnedPRIdentifier) -> Bool {
        all().contains(id)
    }

    func clearAll() {
        save([])
    }

    private func save(_ ids: [PinnedPRIdentifier]) {
        if let data = try? JSONEncoder().encode(ids) {
            defaults.set(data, forKey: pinnedPRsKey)
        }
    }
}
