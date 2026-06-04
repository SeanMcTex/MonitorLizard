import Foundation
@testable import MonitorLizard

actor MockShellExecutor: ShellExecuting {
    private(set) var getAuthenticatedHostsCallCount = 0
    private(set) var executeCalls: [(command: String, arguments: [String])] = []

    private let defaultResponse: Result<String, Error>
    // Checked in order; first matcher whose string appears in the joined arguments wins.
    private let responseMatchers: [(matcher: String, response: Result<String, Error>)]

    init(
        executeResponse: Result<String, Error> = .success("[]"),
        executeResponseMatchers: [(String, Result<String, Error>)] = []
    ) {
        self.defaultResponse = executeResponse
        self.responseMatchers = executeResponseMatchers.map { (matcher: $0.0, response: $0.1) }
    }

    func execute(command: String, arguments: [String], timeout: TimeInterval, host: String?) async throws -> String {
        executeCalls.append((command: command, arguments: arguments))
        let argString = arguments.joined(separator: " ")
        for (matcher, response) in responseMatchers {
            if argString.contains(matcher) {
                return try response.get()
            }
        }
        return try defaultResponse.get()
    }

    func getAuthenticatedHosts() async throws -> [String] {
        getAuthenticatedHostsCallCount += 1
        return ["github.com"]
    }

    func checkGHInstalled() async throws -> Bool { true }
    func checkGHAuthenticated() async throws -> Bool { true }
}
