import Testing
import Foundation
@testable import MonitorLizard

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