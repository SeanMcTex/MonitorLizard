import Foundation

enum ShellError: Error {
    case executionFailed(String)
    case invalidOutput
    case commandNotFound
    case networkError(String)

    var localizedDescription: String {
        switch self {
        case .executionFailed(let message):
            return "Command failed: \(message)"
        case .invalidOutput:
            return "Invalid command output"
        case .commandNotFound:
            return "Command not found"
        case .networkError:
            return "Network connection unavailable. Please check your internet connection."
        }
    }
}

/// ShellExecutor runs shell commands. Each invocation creates its own
/// `Process`, so concurrent calls are safe. Marked as `final class`
/// (not `actor`) to allow true parallelism in task groups.
final class ShellExecutor: Sendable {
    func execute(command: String, arguments: [String] = [], timeout: TimeInterval = 30, host: String? = nil) async throws -> String {
        let process = Process()

        // Set up the process
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments

        // Set PATH to include Homebrew and common installation locations
        var environment = ProcessInfo.processInfo.environment
        let homebrewPaths = [
            "/opt/homebrew/bin",      // Apple Silicon Homebrew
            "/usr/local/bin",          // Intel Homebrew
            "/opt/homebrew/sbin",
            "/usr/local/sbin"
        ]
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let newPath = (homebrewPaths + [existingPath]).joined(separator: ":")
        environment["PATH"] = newPath

        // Set GH_HOST to target a specific GitHub host (e.g. enterprise)
        if let host = host {
            environment["GH_HOST"] = host
        }

        process.environment = environment

        // Set up pipes for output and error.
        // Collect data as it arrives via readabilityHandler to avoid
        // deadlock when output exceeds the pipe buffer (~64KB).
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputAccumulator = PipeAccumulator()
        let errorAccumulator = PipeAccumulator()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { outputAccumulator.append(data) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errorAccumulator.append(data) }
        }

        // Wait for completion without blocking the cooperative thread pool.
        // terminationHandler must be set BEFORE run() to avoid a race
        // where the process finishes before the handler is installed.
        let timedOut = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            var resumed = false
            let lock = NSLock()

            process.terminationHandler = { _ in
                lock.lock()
                guard !resumed else { lock.unlock(); return }
                resumed = true
                lock.unlock()
                continuation.resume(returning: false)
            }

            do {
                try process.run()
            } catch {
                // Clear the handler so we don't double-resume
                process.terminationHandler = nil
                lock.lock()
                resumed = true
                lock.unlock()
                continuation.resume(throwing: ShellError.commandNotFound)
                return
            }

            // Timeout: terminate the process if it hasn't finished in time
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                lock.lock()
                guard !resumed else { lock.unlock(); return }
                resumed = true
                lock.unlock()
                process.terminate()
                continuation.resume(returning: true)
            }
        }

        // Stop reading handlers and drain remaining data
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputAccumulator.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorAccumulator.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        if timedOut {
            throw ShellError.executionFailed("Command timed out after \(Int(timeout)) seconds")
        }

        let outputData = outputAccumulator.data
        let errorData = errorAccumulator.data

        // Check exit status
        guard process.terminationStatus == 0 else {
            let errorMessage = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"

            // Detect network-related errors from gh CLI output
            // When network is unavailable, gh returns messages like:
            // - "error connecting to api.github.com"
            // - "check your internet connection"
            // These patterns help distinguish network issues from auth/permission errors
            let networkErrorPatterns = [
                "error connecting",
                "check your internet connection",
                "could not resolve host",
                "network is unreachable",
                "dial tcp",
                "no such host",
                "connection refused",
                "i/o timeout",
                "unable to connect",
                "failed to connect"
            ]

            let lowercaseMessage = errorMessage.lowercased()
            for pattern in networkErrorPatterns {
                if lowercaseMessage.contains(pattern) {
                    throw ShellError.networkError(errorMessage)
                }
            }

            throw ShellError.executionFailed(errorMessage)
        }

        // Return output
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw ShellError.invalidOutput
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns all GitHub hosts the user is authenticated with (e.g. ["github.com", "github.enterprise.com"])
    func getAuthenticatedHosts() async throws -> [String] {
        do {
            let output = try await execute(command: "gh", arguments: ["auth", "status"])
            return parseHosts(from: output)
        } catch let ShellError.executionFailed(message) {
            // gh auth status exits with non-zero if any host has issues,
            // but still prints host info to stderr/stdout
            return parseHosts(from: message)
        } catch {
            return ["github.com"]  // Fallback to default
        }
    }

    private func parseHosts(from output: String) -> [String] {
        // gh auth status output has hostnames at the start of lines (no leading whitespace)
        // e.g.:
        // github.com
        //   ✓ Logged in to github.com account user (keyring)
        // enterprise.example.com
        //   ✓ Logged in to enterprise.example.com account user (keyring)
        var hosts: [String] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Host lines start at column 0 (no leading whitespace) and contain a dot
            if !trimmed.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("\t") && trimmed.contains(".") && !trimmed.contains(" ") {
                hosts.append(trimmed)
            }
        }
        return hosts.isEmpty ? ["github.com"] : hosts
    }

    func checkGHInstalled() async throws -> Bool {
        do {
            _ = try await execute(command: "which", arguments: ["gh"])
            return true
        } catch {
            return false
        }
    }

    func checkGHAuthenticated() async throws -> Bool {
        do {
            let output = try await execute(command: "gh", arguments: ["auth", "status"])
            return output.contains("Logged in")
        } catch let ShellError.networkError(message) {
            // Re-throw network errors so they can be handled properly upstream
            // Important: Don't confuse network errors with authentication failures
            throw ShellError.networkError(message)
        } catch let ShellError.executionFailed(message) {
            // Backup check for network errors that weren't caught by execute()
            // Note: When offline, `gh auth status` may report "token is invalid"
            // but actual API calls like `gh search prs` give proper "error connecting" messages
            let networkErrorPatterns = [
                "error connecting",
                "check your internet connection",
                "could not resolve host",
                "network is unreachable",
                "dial tcp",
                "no such host",
                "connection refused",
                "i/o timeout",
                "unable to connect"
            ]

            let lowercaseMessage = message.lowercased()
            for pattern in networkErrorPatterns {
                if lowercaseMessage.contains(pattern) {
                    throw ShellError.networkError(message)
                }
            }

            // If not a network error, this is likely an auth issue
            return false
        } catch {
            return false
        }
    }
}

/// Thread-safe accumulator for pipe data collected via readabilityHandler.
private final class PipeAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
