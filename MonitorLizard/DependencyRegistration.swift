import Dependencies
import Foundation

final class UserDefaultsStore: @unchecked Sendable {
    // @unchecked Sendable wraps UserDefaults, which is inherently thread-safe for all operations used here.
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

    /// Provides access to the underlying `UserDefaults` for APIs that require it directly,
    /// such as KVO publishers (`publisher(for:)`) used to observe preference changes.
    ///
    /// - Important: This escape hatch exists solely for `UserDefaults` interop features that
    ///   cannot be expressed through `UserDefaultsStore`'s typed interface. Do **not** use it
    ///   to bypass `PreferenceKeys` — prefer adding a typed accessor to `UserDefaultsStore` instead.
    var underlyingDefaults: UserDefaults {
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
        UserDefaultsStore(defaults: UserDefaults(suiteName: "co.pointfree.dependencies.preview")!)
    }
}

extension WatchlistService: DependencyKey {
    public static var liveValue: WatchlistService {
        WatchlistService()
    }

    public static var testValue: WatchlistService {
        WatchlistService()
    }
}

extension NotificationService: DependencyKey {
    public static var liveValue: NotificationService {
        NotificationService()
    }

    public static var testValue: NotificationService {
        NotificationService()
    }
}

extension PRCacheService: DependencyKey {
    public static var liveValue: PRCacheService {
        PRCacheService()
    }

    public static var testValue: PRCacheService {
        PRCacheService()
    }
}

extension OtherPRsService: DependencyKey {
    public static var liveValue: OtherPRsService {
        OtherPRsService()
    }

    public static var testValue: OtherPRsService {
        OtherPRsService()
    }
}

extension CustomNamesService: DependencyKey {
    public static var liveValue: CustomNamesService {
        CustomNamesService()
    }

    public static var testValue: CustomNamesService {
        CustomNamesService()
    }
}

enum ShellExecutorKey: DependencyKey {
    public static var liveValue: any ShellExecuting {
        ShellExecutor()
    }

    public static var testValue: any ShellExecuting {
        UnimplementedShellExecutor()
    }
}

extension GitHubService: DependencyKey {
    public static var liveValue: GitHubService {
        GitHubService()
    }

    public static var testValue: GitHubService {
        GitHubService()
    }
}

private struct UnimplementedShellExecutor: ShellExecuting {
    func execute(command: String, arguments: [String], timeout: TimeInterval, host: String?) async throws -> String {
        reportIssue("Unimplemented: ShellExecuting.execute called without a test override")
        return ""
    }

    func getAuthenticatedHosts() async throws -> [String] {
        reportIssue("Unimplemented: ShellExecuting.getAuthenticatedHosts called without a test override")
        return []
    }

    func checkGHInstalled() async throws -> Bool {
        reportIssue("Unimplemented: ShellExecuting.checkGHInstalled called without a test override")
        return false
    }

    func checkGHAuthenticated() async throws -> Bool {
        reportIssue("Unimplemented: ShellExecuting.checkGHAuthenticated called without a test override")
        return false
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
