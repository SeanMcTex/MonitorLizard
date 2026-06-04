import Dependencies
import Foundation

final class UserDefaultsStore: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func testSuite() -> UserDefaultsStore {
        UserDefaultsStore(defaults: UserDefaults(suiteName: "co.pointfree.dependencies.test.\(UUID().uuidString)")!)
    }

    func bool(forKey key: PreferenceKeys) -> Bool {
        defaults.bool(forKey: key.rawValue)
    }

    func object(forKey key: PreferenceKeys) -> Any? {
        defaults.object(forKey: key.rawValue)
    }

    func string(forKey key: PreferenceKeys) -> String? {
        defaults.string(forKey: key.rawValue)
    }

    func integer(forKey key: PreferenceKeys) -> Int {
        defaults.integer(forKey: key.rawValue)
    }

    func data(forKey key: PreferenceKeys) -> Data? {
        defaults.data(forKey: key.rawValue)
    }

    func dictionary(forKey key: PreferenceKeys) -> [String: Any]? {
        defaults.dictionary(forKey: key.rawValue)
    }

    func set(_ value: Bool, forKey key: PreferenceKeys) {
        defaults.set(value, forKey: key.rawValue)
    }

    func set(_ value: Int, forKey key: PreferenceKeys) {
        defaults.set(value, forKey: key.rawValue)
    }

    func set(_ value: String, forKey key: PreferenceKeys) {
        defaults.set(value, forKey: key.rawValue)
    }

    func set(_ value: Data, forKey key: PreferenceKeys) {
        defaults.set(value, forKey: key.rawValue)
    }

    func set(_ value: [String: Any], forKey key: PreferenceKeys) {
        defaults.set(value, forKey: key.rawValue)
    }

    func removeObject(forKey key: PreferenceKeys) {
        defaults.removeObject(forKey: key.rawValue)
    }

    func register(defaults registration: [String: Any]) {
        defaults.register(defaults: registration)
    }

    var underlyingDefaults: UserDefaults {
        defaults
    }
}

// MARK: - DependencyKey registrations

extension UserDefaultsStore: DependencyKey {
    public static let liveValue = UserDefaultsStore(defaults: .standard)

    public static var testValue: UserDefaultsStore {
        UserDefaultsStore(defaults: UserDefaults(suiteName: "co.pointfree.dependencies.test")!)
    }

    public static let previewValue = UserDefaultsStore(defaults: UserDefaults(suiteName: "co.pointfree.dependencies.preview")!)
}

extension WatchlistService: DependencyKey {
    public static let liveValue = WatchlistService(defaults: UserDefaultsStore.liveValue)

    public static var testValue: WatchlistService {
        WatchlistService(defaults: UserDefaultsStore.testValue)
    }
}

extension NotificationService: DependencyKey {
    public static let liveValue = NotificationService(defaults: UserDefaultsStore.liveValue)

    public static var testValue: NotificationService {
        NotificationService(defaults: UserDefaultsStore.testValue)
    }
}

extension PRCacheService: DependencyKey {
    public static let liveValue = PRCacheService(defaults: UserDefaultsStore.liveValue)

    public static var testValue: PRCacheService {
        PRCacheService(defaults: UserDefaultsStore.testValue)
    }
}

extension OtherPRsService: DependencyKey {
    public static let liveValue = OtherPRsService(defaults: UserDefaultsStore.liveValue)

    public static var testValue: OtherPRsService {
        OtherPRsService(defaults: UserDefaultsStore.testValue)
    }
}

extension CustomNamesService: DependencyKey {
    public static let liveValue = CustomNamesService(defaults: UserDefaultsStore.liveValue)

    public static var testValue: CustomNamesService {
        CustomNamesService(defaults: UserDefaultsStore.testValue)
    }
}

enum ShellExecutorKey: DependencyKey {
    public static var liveValue: any ShellExecuting {
        ShellExecutor()
    }

    public static var testValue: any ShellExecuting {
        ShellExecutor()
    }
}

extension GitHubService: DependencyKey {
    public static let liveValue = GitHubService()

    public static var testValue: GitHubService {
        GitHubService()
    }
}

// MARK: - DependencyValues accessors

extension DependencyValues {
    var userDefaults: UserDefaultsStore {
        get { self[UserDefaultsStore.self] }
        set { self[UserDefaultsStore.self] = newValue }
    }

    var watchlistService: WatchlistService {
        get { self[WatchlistService.self] }
        set { self[WatchlistService.self] = newValue }
    }

    var notificationService: NotificationService {
        get { self[NotificationService.self] }
        set { self[NotificationService.self] = newValue }
    }

    var cacheService: PRCacheService {
        get { self[PRCacheService.self] }
        set { self[PRCacheService.self] = newValue }
    }

    var otherPRsService: OtherPRsService {
        get { self[OtherPRsService.self] }
        set { self[OtherPRsService.self] = newValue }
    }

    var customNamesService: CustomNamesService {
        get { self[CustomNamesService.self] }
        set { self[CustomNamesService.self] = newValue }
    }

    var shellExecutor: any ShellExecuting {
        get { self[ShellExecutorKey.self] }
        set { self[ShellExecutorKey.self] = newValue }
    }

    var githubService: GitHubService {
        get { self[GitHubService.self] }
        set { self[GitHubService.self] = newValue }
    }
}