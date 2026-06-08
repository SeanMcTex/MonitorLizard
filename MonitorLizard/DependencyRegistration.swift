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

enum WatchlistServiceKey: DependencyKey {
    public static var liveValue: any WatchlistServicing {
        WatchlistService()
    }

    public static var testValue: any WatchlistServicing {
        UnimplementedWatchlistService()
    }

    public static var previewValue: any WatchlistServicing {
        WatchlistService()
    }
}

enum NotificationServiceKey: DependencyKey {
    public static var liveValue: any NotificationServicing {
        NotificationService()
    }

    public static var testValue: any NotificationServicing {
        UnimplementedNotificationService()
    }

    public static var previewValue: any NotificationServicing {
        NotificationService()
    }
}

enum PRCacheServiceKey: DependencyKey {
    public static var liveValue: any PRCacheServicing {
        PRCacheService()
    }

    public static var testValue: any PRCacheServicing {
        UnimplementedPRCacheService()
    }

    public static var previewValue: any PRCacheServicing {
        PRCacheService()
    }
}

enum OtherPRsServiceKey: DependencyKey {
    public static var liveValue: any OtherPRsServicing {
        OtherPRsService()
    }

    public static var testValue: any OtherPRsServicing {
        UnimplementedOtherPRsService()
    }

    public static var previewValue: any OtherPRsServicing {
        OtherPRsService()
    }
}

enum CustomNamesServiceKey: DependencyKey {
    public static var liveValue: any CustomNamesServicing {
        CustomNamesService()
    }

    public static var testValue: any CustomNamesServicing {
        UnimplementedCustomNamesService()
    }

    public static var previewValue: any CustomNamesServicing {
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

enum GitHubServiceKey: DependencyKey {
    @MainActor public static var liveValue: any GitHubServicing {
        GitHubService()
    }

    public static var testValue: any GitHubServicing {
        UnimplementedGitHubService()
    }

    @MainActor public static var previewValue: any GitHubServicing {
        GitHubService()
    }
}

enum PasteboardClientKey: DependencyKey {
    public static var liveValue: any PasteboardClient {
        LivePasteboardClient()
    }

    public static var testValue: any PasteboardClient {
        TestPasteboardClient()
    }

    public static var previewValue: any PasteboardClient {
        LivePasteboardClient()
    }
}

// MARK: - Unimplemented test doubles

private struct UnimplementedWatchlistService: WatchlistServicing {
    func watch(_ pr: PullRequest) {
        reportIssue("Unimplemented: WatchlistServicing.watch called without a test override")
    }

    func unwatch(_ pr: PullRequest) {
        reportIssue("Unimplemented: WatchlistServicing.unwatch called without a test override")
    }

    func isWatched(_ pr: PullRequest) -> Bool {
        reportIssue("Unimplemented: WatchlistServicing.isWatched called without a test override")
        return false
    }

    func checkForCompletions(currentPRs: [PullRequest]) -> [PullRequest] {
        reportIssue("Unimplemented: WatchlistServicing.checkForCompletions called without a test override")
        return []
    }

    func checkForUpdates(currentPRs: [PullRequest]) -> [PullRequest] {
        reportIssue("Unimplemented: WatchlistServicing.checkForUpdates called without a test override")
        return []
    }

    func getWatchedStatus(for prId: String) -> WatchlistService.WatchedPRInfo? {
        reportIssue("Unimplemented: WatchlistServicing.getWatchedStatus called without a test override")
        return nil
    }

    func clearAll() {
        reportIssue("Unimplemented: WatchlistServicing.clearAll called without a test override")
    }
}

private struct UnimplementedNotificationService: NotificationServicing {
    func requestAuthorization() async throws {
        reportIssue("Unimplemented: NotificationServicing.requestAuthorization called without a test override")
    }

    func notifyBuildComplete(pr: PullRequest, status: BuildStatus) {
        reportIssue("Unimplemented: NotificationServicing.notifyBuildComplete called without a test override")
    }

    func notifyPRUpdated(pr: PullRequest) {
        reportIssue("Unimplemented: NotificationServicing.notifyPRUpdated called without a test override")
    }
}

private struct UnimplementedPRCacheService: PRCacheServicing {
    func save(mainPRs: [PullRequest], otherPRs: [PullRequest]) {
        reportIssue("Unimplemented: PRCacheServicing.save called without a test override")
    }

    func loadMainPRs() -> [PullRequest] {
        reportIssue("Unimplemented: PRCacheServicing.loadMainPRs called without a test override")
        return []
    }

    func loadOtherPRs() -> [PullRequest] {
        reportIssue("Unimplemented: PRCacheServicing.loadOtherPRs called without a test override")
        return []
    }
}

private struct UnimplementedOtherPRsService: OtherPRsServicing {
    func add(_ id: OtherPRIdentifier) {
        reportIssue("Unimplemented: OtherPRsServicing.add called without a test override")
    }

    func remove(_ id: OtherPRIdentifier) {
        reportIssue("Unimplemented: OtherPRsServicing.remove called without a test override")
    }

    func all() -> [OtherPRIdentifier] {
        reportIssue("Unimplemented: OtherPRsServicing.all called without a test override")
        return []
    }

    func contains(_ id: OtherPRIdentifier) -> Bool {
        reportIssue("Unimplemented: OtherPRsServicing.contains called without a test override")
        return false
    }

    func clearAll() {
        reportIssue("Unimplemented: OtherPRsServicing.clearAll called without a test override")
    }
}

private struct UnimplementedCustomNamesService: CustomNamesServicing {
    func setName(_ name: String, for prID: String) {
        reportIssue("Unimplemented: CustomNamesServicing.setName called without a test override")
    }

    func removeName(for prID: String) {
        reportIssue("Unimplemented: CustomNamesServicing.removeName called without a test override")
    }

    func name(for prID: String) -> String? {
        reportIssue("Unimplemented: CustomNamesServicing.name called without a test override")
        return nil
    }

    func allNames() -> [String: String] {
        reportIssue("Unimplemented: CustomNamesServicing.allNames called without a test override")
        return [:]
    }

    func pruneStale(keeping activeIDs: Set<String>) {
        reportIssue("Unimplemented: CustomNamesServicing.pruneStale called without a test override")
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

@MainActor private final class UnimplementedGitHubService: GitHubServicing {
    func checkGHAvailable() async throws {
        reportIssue("Unimplemented: GitHubServicing.checkGHAvailable called without a test override")
    }

    func invalidateHostsCache() {
        reportIssue("Unimplemented: GitHubServicing.invalidateHostsCache called without a test override")
    }

    func fetchAllOpenPRs(enableInactiveDetection: Bool, inactiveThresholdDays: Int, isDemoMode: Bool) async throws -> PRFetchResult {
        reportIssue("Unimplemented: GitHubServicing.fetchAllOpenPRs called without a test override")
        return PRFetchResult(pullRequests: [], isPartial: false)
    }

    func fetchPRStatus(owner: String, repo: String, number: Int, updatedAt: Date, enableInactiveDetection: Bool, inactiveThresholdDays: Int, host: String) async throws -> (status: BuildStatus, headRefName: String, statusChecks: [StatusCheck], reviewDecision: ReviewDecision?) {
        reportIssue("Unimplemented: GitHubServicing.fetchPRStatus called without a test override")
        return (.success, "", [], nil)
    }

    func fetchOtherPR(_ id: OtherPRIdentifier, enableInactiveDetection: Bool, inactiveThresholdDays: Int) async throws -> PullRequest? {
        reportIssue("Unimplemented: GitHubServicing.fetchOtherPR called without a test override")
        return nil
    }
}

// MARK: - DependencyValues accessors

extension DependencyValues {
    var userDefaults: UserDefaultsStore {
        get { self[UserDefaultsStore.self] }
        set { self[UserDefaultsStore.self] = newValue }
    }

    var watchlistService: any WatchlistServicing {
        get { self[WatchlistServiceKey.self] }
        set { self[WatchlistServiceKey.self] = newValue }
    }

    var notificationService: any NotificationServicing {
        get { self[NotificationServiceKey.self] }
        set { self[NotificationServiceKey.self] = newValue }
    }

    var cacheService: any PRCacheServicing {
        get { self[PRCacheServiceKey.self] }
        set { self[PRCacheServiceKey.self] = newValue }
    }

    var otherPRsService: any OtherPRsServicing {
        get { self[OtherPRsServiceKey.self] }
        set { self[OtherPRsServiceKey.self] = newValue }
    }

    var customNamesService: any CustomNamesServicing {
        get { self[CustomNamesServiceKey.self] }
        set { self[CustomNamesServiceKey.self] = newValue }
    }

    var shellExecutor: any ShellExecuting {
        get { self[ShellExecutorKey.self] }
        set { self[ShellExecutorKey.self] = newValue }
    }

    var githubService: any GitHubServicing {
        get { self[GitHubServiceKey.self] }
        set { self[GitHubServiceKey.self] = newValue }
    }

    var pasteboardClient: any PasteboardClient {
        get { self[PasteboardClientKey.self] }
        set { self[PasteboardClientKey.self] = newValue }
    }
}
