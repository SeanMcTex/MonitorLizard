import Foundation
import os

/// Abstraction over shell command execution. Enables test doubles to be injected into services.
protocol ShellExecuting: Sendable {
    func execute(command: String, arguments: [String], timeout: TimeInterval, host: String?) async throws -> String
    func getAuthenticatedHosts() async throws -> [String]
    func checkGHInstalled() async throws -> Bool
    func checkGHAuthenticated() async throws -> Bool
}

extension ShellExecuting {
    /// Convenience overload used by most call sites — omits timeout (defaults to 30 s).
    func execute(command: String, arguments: [String] = [], host: String? = nil) async throws -> String {
        try await execute(command: command, arguments: arguments, timeout: 30, host: host)
    }
}

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
final class ShellExecutor: ShellExecuting {
    nonisolated func execute(command: String, arguments: [String] = [], timeout: TimeInterval = 30, host: String? = nil) async throws -> String {
        let process = Process()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments

        var environment = ProcessInfo.processInfo.environment
        let homebrewPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/homebrew/sbin",
            "/usr/local/sbin"
        ]
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (homebrewPaths + [existingPath]).joined(separator: ":")

        if let host {
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

        // OSAllocatedUnfairLock<Data> is safe to use from readabilityHandler
        // callbacks (background threads) and from async contexts alike.
        let outputBuffer = OSAllocatedUnfairLock(initialState: Data())
        let errorBuffer = OSAllocatedUnfairLock(initialState: Data())

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { outputBuffer.withLock { $0.append(data) } }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errorBuffer.withLock { $0.append(data) } }
        }

        // Wait for completion without blocking the cooperative thread pool.
        // terminationHandler must be set BEFORE run() to avoid a race
        // where the process finishes before the handler is installed.
        //
        // resumedLock holds "already resumed" state. Both the terminationHandler
        // and the timeout Task race to flip it; only the first caller wins.
        let timedOut = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            let resumedLock = OSAllocatedUnfairLock(initialState: false)

            process.terminationHandler = { _ in
                let alreadyResumed = resumedLock.withLock { state -> Bool in
                    defer { state = true }
                    return state
                }
                if !alreadyResumed { continuation.resume(returning: false) }
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                let alreadyResumed = resumedLock.withLock { state -> Bool in
                    defer { state = true }
                    return state
                }
                if !alreadyResumed { continuation.resume(throwing: ShellError.commandNotFound) }
                return
            }

            // Timeout: terminate the process if it hasn't finished in time.
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                let alreadyResumed = resumedLock.withLock { state -> Bool in
                    defer { state = true }
                    return state
                }
                if !alreadyResumed {
                    process.terminate()
                    continuation.resume(returning: true)
                }
            }
        }

        // Stop reading handlers and drain remaining data.
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputBuffer.withLock { $0.append(outputPipe.fileHandleForReading.readDataToEndOfFile()) }
        errorBuffer.withLock { $0.append(errorPipe.fileHandleForReading.readDataToEndOfFile()) }

        if timedOut {
            throw ShellError.executionFailed("Command timed out after \(Int(timeout)) seconds")
        }

        let outputData = outputBuffer.withLock { $0 }
        let errorData = errorBuffer.withLock { $0 }

        guard process.terminationStatus == 0 else {
            let errorMessage = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"

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

        guard let output = String(data: outputData, encoding: .utf8) else {
            throw ShellError.invalidOutput
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns all GitHub hosts the user is authenticated with (e.g. ["github.com", "github.enterprise.com"])
    nonisolated func getAuthenticatedHosts() async throws -> [String] {
        do {
            let output = try await execute(command: "gh", arguments: ["auth", "status"])
            return Self.parseHosts(from: output)
        } catch let ShellError.executionFailed(message) {
            // gh auth status exits with non-zero if any host has issues,
            // but still prints host info to stderr/stdout
            return Self.parseHosts(from: message)
        } catch {
            return ["github.com"]
        }
    }

    nonisolated private static func parseHosts(from output: String) -> [String] {
        var hosts: [String] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("\t") && trimmed.contains(".") && !trimmed.contains(" ") {
                hosts.append(trimmed)
            }
        }
        return hosts.isEmpty ? ["github.com"] : hosts
    }

    nonisolated func checkGHInstalled() async throws -> Bool {
        do {
            _ = try await execute(command: "which", arguments: ["gh"])
            return true
        } catch {
            return false
        }
    }

    nonisolated func checkGHAuthenticated() async throws -> Bool {
        do {
            let output = try await execute(command: "gh", arguments: ["auth", "status"])
            return output.contains("Logged in")
        } catch let ShellError.networkError(message) {
            throw ShellError.networkError(message)
        } catch let ShellError.executionFailed(message) {
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

            return false
        } catch {
            return false
        }
    }
}
