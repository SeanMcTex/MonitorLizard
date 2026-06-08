import Foundation

enum PreferenceKeys: String, Sendable {
    case refreshInterval
    case sortNonSuccessFirst
    case showReviewPRs
    case enableSounds
    case enableVoice
    case voiceAnnouncementTextBuildComplete
    case voiceAnnouncementTextPRUpdated
    case showNotifications
    case enableInactiveBranchDetection
    case hideInactivePRs
    case inactiveBranchThresholdDays
    case selectedRepository

    case watchedPRs
    case cachedMainPRs
    case cachedOtherPRs
    case pinnedPRs
    case customPRNames
}

extension PreferenceKeys: CustomStringConvertible {
    var description: String { rawValue }
}
