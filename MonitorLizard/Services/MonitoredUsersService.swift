import Foundation
import Combine

class MonitoredUsersService: ObservableObject {
    static let shared = MonitoredUsersService()

    private let defaults: UserDefaults
    private let usersKey = "monitoredUsers"
    private let selectedKey = "selectedUserId"

    @Published var users: [MonitoredUser] = []
    @Published var selectedUserId: UUID?

    var selectedUser: MonitoredUser? {
        users.first { $0.id == selectedUserId }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadUsers()
    }

    private func loadUsers() {
        if let data = defaults.data(forKey: usersKey),
           let decoded = try? JSONDecoder().decode([MonitoredUser].self, from: data),
           !decoded.isEmpty {
            users = decoded
        } else {
            users = [.defaultMe()]
            saveUsers()
        }

        if let idString = defaults.string(forKey: selectedKey),
           let id = UUID(uuidString: idString),
           users.contains(where: { $0.id == id }) {
            selectedUserId = id
        } else {
            selectedUserId = users.first?.id
            saveSelectedId()
        }
    }

    func addUser(username: String, displayName: String?) {
        let user = MonitoredUser(
            id: UUID(),
            username: username,
            displayName: displayName?.isEmpty == true ? nil : displayName,
            ignoredRepos: [],
            ignoredChecks: []
        )
        users.append(user)
        saveUsers()
    }

    func removeUser(id: UUID) {
        guard let user = users.first(where: { $0.id == id }), !user.isMe else { return }
        users.removeAll { $0.id == id }
        if selectedUserId == id {
            selectedUserId = users.first?.id
            saveSelectedId()
        }
        saveUsers()
    }

    func updateUser(_ user: MonitoredUser) {
        guard let index = users.firstIndex(where: { $0.id == user.id }) else { return }
        users[index] = user
        saveUsers()
    }

    func notifyConfigurationChanged() {
        users = users
    }

    func selectUser(id: UUID) {
        guard users.contains(where: { $0.id == id }) else { return }
        selectedUserId = id
        saveSelectedId()
    }

    private func saveUsers() {
        if let data = try? JSONEncoder().encode(users) {
            defaults.set(data, forKey: usersKey)
        }
    }

    private func saveSelectedId() {
        defaults.set(selectedUserId?.uuidString, forKey: selectedKey)
    }
}
