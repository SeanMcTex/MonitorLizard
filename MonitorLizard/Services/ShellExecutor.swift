import Foundation

enum ShellError: Error {
    case executionFailed(String)
    case invalidOutput
    case commandNotFound

    var localizedDescription: String {
        switch self {
        case .executionFailed(let message):
            return "Command failed: \(message)"
        case .invalidOutput:
            return "Invalid command output"
        case .commandNotFound:
            return "Command not found"
        }
    }
}

actor ShellExecutor {
    func execute(command: String, arguments: [String] = [], timeout: TimeInterval = 30) async throws -> String {
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
        process.environment = environment

        // Set up pipes for output and error
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Launch the process
        do {
            try process.run()
        } catch {
            throw ShellError.commandNotFound
        }

        // Wait for completion with timeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if process.isRunning {
                process.terminate()
                throw ShellError.executionFailed("Command timed out after \(timeout) seconds")
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        // Read output
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        // Check exit status
        guard process.terminationStatus == 0 else {
            let errorMessage = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw ShellError.executionFailed(errorMessage)
        }

        // Return output
        guard let output = String(data: outputData, encoding: .utf8) else {
            throw ShellError.invalidOutput
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
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
        } catch {
            return false
        }
    }
}
