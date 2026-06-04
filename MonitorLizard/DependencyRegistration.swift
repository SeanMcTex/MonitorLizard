import Dependencies
import Foundation

final class UserDefaultsStore: @unchecked Sendable {
    nonisolated(unsafe) private let defaults: UserDefaults

    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    nonisolated static func testSuite() -> UserDefaultsStore {
        UserDefaultsStore(defaults: UserDefaults(suiteName: "co.pointfree.dependencies.test.\(UUID().uuidString)")!)
    }

    nonisolated func bool(forKey key: PreferenceKeys) -> Bool {
        defaults.bool(forKey: key.rawValue)
    }

    nonisolated func object(forKey key: PreferenceKeys) -> Any? {
        defaults.object(forKey: key.rawValue)
    }

    nonisolated func string(forKey key: PreferenceKeys) -> String? {
        defaults.string(forKey: key.rawValue)
    }

    nonisolated func integer(forKey key: PreferenceKeys) -> Int {
        defaults.integer(forKey: key.rawValue)
    }

    nonisolated func data(forKey key: PreferenceKeys) -> Data? {
        defaults.data(forKey: key.rawValue)
    }

    nonisolated func dictionary(forKey key: PreferenceKeys) -> [String: Any]? {
        defaults.dictionary(forKey: key.rawValue)
    }

    nonisolated func set(_ value: Bool, forKey key: PreferenceKeys) {
        defaults.set(value, forKey: key.rawValue)
    }

    nonisolated func set(_ value: Int, forKey key: PreferenceKeys) {
        defaults.set(value, forKey: key.rawValue)
    }

    nonisolated func set(_ value: String, forKey key: PreferenceKeys) {
        defaults.set(value, forKey: key.rawValue)
    }

    nonisolated func set(_ value: Data, forKey key: PreferenceKeys) {
        defaults.set(value, forKey: key.rawValue)
    }

    nonisolated func set(_ value: [String: Any], forKey key: PreferenceKeys) {
        defaults.set(value, forKey: key.rawValue)
    }

    nonisolated func removeObject(forKey key: PreferenceKeys) {
        defaults.removeObject(forKey: key.rawValue)
    }

    nonisolated func register(defaults registration: [String: Any]) {
        defaults.register(defaults: registration)
    }

    nonisolated var underlyingDefaults: UserDefaults {
        defaults
    }
}

// MARK: - DependencyKey registrations

extension UserDefaultsStore: DependencyKey {
    public static var liveValue: UserDefaultsStore {
        UserDefaultsStore(defaults: .standard)
    }

    public static var testValue: UserDefaultsStore {
        UserDefaultsStore(defaults: UserDefaults(suiteName: "co.pointfree.dependencies.test.\(UUID().uuidString)")!)
    }

    public static var previewValue: UserDefaultsStore {
        UserDefaultsStore(defaults: .standard)
    }
}

extension WatchlistService: DependencyKey {
    public static var liveValue: WatchlistService {
        WatchlistService(defaults: .liveValue)
    }

    public static var testValue: WatchlistService {
        WatchlistService(defaults: .testValue)
    }
}

extension NotificationService: DependencyKey {
    public static var liveValue: NotificationService {
        NotificationService(defaults: .liveValue)
    }

    public static var testValue: NotificationService {
        NotificationService(defaults: .testValue)
    }
}

extension PRCacheService: DependencyKey {
    public static var liveValue: PRCacheService {
        PRCacheService(defaults: .liveValue)
    }

    public static var testValue: PRCacheService {
        PRCacheService(defaults: .testValue)
    }
}

extension OtherPRsService: DependencyKey {
    public static var liveValue: OtherPRsService {
        OtherPRsService(defaults: .liveValue)
    }

    public static var testValue: OtherPRsService {
        OtherPRsService(defaults: .testValue)
    }
}

extension CustomNamesService: DependencyKey {
    public static var liveValue: CustomNamesService {
        CustomNamesService(defaults: .liveValue)
    }

    public static var testValue: CustomNamesService {
        CustomNamesService(defaults: .testValue)
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
}