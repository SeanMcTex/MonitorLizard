import Testing
import Foundation
@testable import MonitorLizard

@MainActor
struct GitHubServiceFetchErrorTests {

    enum GitHubErrorMappingScenario: CaseIterable, Sendable {
        case networkError
        case commandNotFound

        var shellError: ShellError {
            switch self {
            case .networkError:
                return .networkError("error connecting to api.github.com")
            case .commandNotFound:
                return .commandNotFound
            }
        }

        var expectedError: GitHubError {
            switch self {
            case .networkError:
                return .networkError
            case .commandNotFound:
                return .notInstalled
            }
        }
    }

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

    @Test(arguments: GitHubErrorMappingScenario.allCases)
    func shellFailureMapsToExpectedGitHubError(scenario: GitHubErrorMappingScenario) async {
        let mock = MockShellExecutor(executeResponse: .failure(scenario.shellError))
        let service = GitHubService(shellExecutor: mock)

        do {
            _ = try await service.fetchAllOpenPRs(enableInactiveDetection: false, inactiveThresholdDays: 3)
            Issue.record("Expected an error to be thrown")
        } catch let error as GitHubError {
            #expect(error == scenario.expectedError)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}