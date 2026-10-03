import Foundation

/// Asserts that the current thread is the main thread.
/// Fires in debug builds only; compiles to a no-op in release.
@_transparent
func assertMainThread(
    file: StaticString = #file,
    line: UInt = #line
) {
    assert(Thread.isMainThread, "Main-thread-only API accessed off the main thread", file: file, line: line)
}

enum Constants {
    // Time intervals
    static let secondsPerDay: TimeInterval = 24 * 60 * 60
    static let defaultRefreshInterval = 30
    static let defaultShellTimeout: TimeInterval = 30
    /// How long a stack's completion lookup is reused across polls before it is
    /// fetched again. The tradeoff: within the interval a companion part's status
    /// or a newly merged position can be up to this stale, but partial stacks are
    /// spared a stack-entries GraphQL query plus per-part detail calls on every
    /// poll; a shorter interval revalidates sooner at more network cost.
    static let stackResolutionRevalidationInterval: TimeInterval = 120

    // Settings defaults
    static let defaultInactiveBranchThreshold = 3
    static let minRefreshInterval = 10
    static let maxRefreshInterval = 300
    static let refreshIntervalStep = 10
    static let minInactiveBranchThreshold = 1
    static let maxInactiveBranchThreshold = 90

    // GitHub API
    static let batchQueryChunkSize = 50

    // UI constants
    static let menuMaxHeightMultiplier = 0.7
    static let settingsWindowWidth = 450.0
    static let settingsWindowHeight = 500.0

    // Voice announcement
    static let defaultVoiceAnnouncementText = "Build ready for Q A"
}
