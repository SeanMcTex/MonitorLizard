import Testing
import Foundation
@testable import MonitorLizard

// MARK: - parseHosts Tests

struct ShellExecutorParseHostsTests {

    @Test func singleHostIsExtracted() {
        let output = """
        github.com
          ✓ Logged in to github.com account alice (keyring)
        """
        #expect(ShellExecutor.parseHosts(from: output) == ["github.com"])
    }

    @Test func multipleHostsAreExtracted() {
        let output = """
        github.com
          ✓ Logged in to github.com account alice (keyring)
        enterprise.example.com
          ✓ Logged in to enterprise.example.com account alice (keyring)
        """
        #expect(ShellExecutor.parseHosts(from: output) == ["github.com", "enterprise.example.com"])
    }

    @Test func emptyOutputFallsBackToGitHubCom() {
        #expect(ShellExecutor.parseHosts(from: "") == ["github.com"])
    }

    @Test func linesWithLeadingWhitespaceAreIgnored() {
        // A hostname-like string with leading whitespace is a status line, not a host declaration.
        let output = "  enterprise.example.com"
        #expect(ShellExecutor.parseHosts(from: output) == ["github.com"])
    }

    @Test func statusLinesContainingSpacesAreIgnored() {
        // Status lines have no leading whitespace but contain spaces between words.
        let output = "✓ Logged in to github.com account alice"
        #expect(ShellExecutor.parseHosts(from: output) == ["github.com"])
    }

    @Test func linesWithoutDotAreIgnored() {
        let output = "notahost\ngithub.com"
        #expect(ShellExecutor.parseHosts(from: output) == ["github.com"])
    }
}

// MARK: - Timeout Tests

struct ShellExecutorTimeoutTests {

    @Test func commandTimesOut() async {
        let executor = ShellExecutor()
        do {
            _ = try await executor.execute(command: "sleep", arguments: ["10"], timeout: 0.1)
            Issue.record("Expected an error to be thrown")
        } catch ShellError.executionFailed(let message) {
            #expect(message.contains("timed out"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
