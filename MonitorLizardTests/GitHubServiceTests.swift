import Testing
import Foundation
@testable import MonitorLizard

// MARK: - Mock

private actor MockShellExecutor: ShellExecuting {
    private(set) var getAuthenticatedHostsCallCount = 0
    private let executeResponse: Result<String, Error>

    init(executeResponse: Result<String, Error> = .success("[]")) {
        self.executeResponse = executeResponse
    }

    func execute(command: String, arguments: [String], timeout: TimeInterval, host: String?) async throws -> String {
        try executeResponse.get()
    }

    func getAuthenticatedHosts() async throws -> [String] {
        getAuthenticatedHostsCallCount += 1
        return ["github.com"]
    }

    func checkGHInstalled() async throws -> Bool { true }
    func checkGHAuthenticated() async throws -> Bool { true }
}

// MARK: - Host Cache Tests

@MainActor
struct GitHubServiceHostCacheTests {

    @Test func hostsAreCachedAfterFirstFetch() async throws {
        let mock = MockShellExecutor()
        let service = GitHubService(shellExecutor: mock)

        _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        #expect(await mock.getAuthenticatedHostsCallCount == 1)

        _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        #expect(await mock.getAuthenticatedHostsCallCount == 1, "second fetch should use the cached hosts")
    }

    @Test func invalidateHostsCacheForcesRefetch() async throws {
        let mock = MockShellExecutor()
        let service = GitHubService(shellExecutor: mock)

        _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        #expect(await mock.getAuthenticatedHostsCallCount == 1)

        service.invalidateHostsCache()

        _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
        #expect(await mock.getAuthenticatedHostsCallCount == 2, "invalidated cache should trigger a re-fetch")
    }
}

// MARK: - Fetch Error Rethrow Tests

@MainActor
struct GitHubServiceFetchErrorTests {

    /// When all fetches fail with a generic execution error (e.g. auth expired), the original
    /// ShellError should propagate — not be swallowed into GitHubError.networkError.
    @Test func executionFailureRethrowsAsShellError() async {
        let mock = MockShellExecutor(executeResponse: .failure(ShellError.executionFailed("token expired or invalid")))
        let service = GitHubService(shellExecutor: mock)

        do {
            _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
            Issue.record("Expected an error to be thrown")
        } catch let error as GitHubError where error == .networkError {
            Issue.record("executionFailed should not be re-mapped to GitHubError.networkError")
        } catch is ShellError {
            // Expected: original ShellError re-thrown as-is
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    /// A genuine network error from the shell (gh CLI) should map to GitHubError.networkError.
    @Test func shellNetworkErrorBecomesGitHubNetworkError() async {
        let mock = MockShellExecutor(executeResponse: .failure(ShellError.networkError("error connecting to api.github.com")))
        let service = GitHubService(shellExecutor: mock)

        do {
            _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
            Issue.record("Expected an error to be thrown")
        } catch let error as GitHubError {
            #expect(error == .networkError)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    /// A missing gh binary should map to GitHubError.notInstalled.
    @Test func commandNotFoundBecomesGitHubNotInstalled() async {
        let mock = MockShellExecutor(executeResponse: .failure(ShellError.commandNotFound))
        let service = GitHubService(shellExecutor: mock)

        do {
            _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
            Issue.record("Expected an error to be thrown")
        } catch let error as GitHubError {
            #expect(error == .notInstalled)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
