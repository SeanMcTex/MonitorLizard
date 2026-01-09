import Foundation

enum Constants {
    // Time intervals
    static let secondsPerDay: TimeInterval = 24 * 60 * 60
    static let defaultRefreshInterval = 30
    static let defaultShellTimeout: TimeInterval = 30

    // Settings defaults
    static let defaultStaleBranchThreshold = 3
    static let minRefreshInterval = 10
    static let maxRefreshInterval = 300
    static let refreshIntervalStep = 10
    static let minStaleBranchThreshold = 1
    static let maxStaleBranchThreshold = 90

    // UI constants
    static let menuMaxHeightMultiplier = 0.7
    static let settingsWindowWidth = 450.0
    static let settingsWindowHeight = 500.0

    // Voice announcement
    static let defaultVoiceAnnouncementText = "Build ready for Q A"
}
