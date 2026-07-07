import AppKit
import AVFoundation
import Dependencies
import Foundation
import UserNotifications

protocol NotificationServicing: Sendable {
    func requestAuthorization() async throws
    func notifyBuildComplete(pr: PullRequest, status: BuildStatus)
    func notifyPRUpdated(pr: PullRequest)
}

/// Posts system notifications, plays sounds, and speaks announcements for build completions.
///
/// - Important: This type is `@unchecked Sendable` because all mutable state is accessed
///   exclusively from the main thread. Calling from a background thread will trigger an
///   assertion failure in debug builds.
final class NotificationService: NotificationServicing, @unchecked Sendable {
    @Dependency(UserDefaultsStore.self) private var defaults

    init() {}

    private var soundsEnabled: Bool {
        assertMainThread()
        return defaults.bool(forKey: PreferenceKeys.enableSounds)
    }

    private var voiceEnabled: Bool {
        assertMainThread()
        return defaults.bool(forKey: PreferenceKeys.enableVoice)
    }

    private var notificationsEnabled: Bool {
        assertMainThread()
        return defaults.bool(forKey: PreferenceKeys.showNotifications)
    }

    private var voiceAnnouncementTextBuildComplete: String {
        assertMainThread()
        return defaults.string(forKey: PreferenceKeys.voiceAnnouncementTextBuildComplete) ?? Constants.defaultVoiceAnnouncementTextBuildComplete
    }

    private var voiceAnnouncementTextPRUpdated: String {
        assertMainThread()
        return defaults.string(forKey: PreferenceKeys.voiceAnnouncementTextPRUpdated) ?? Constants.defaultVoiceAnnouncementTextPRUpdated
    }

    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func notifyPRUpdated(pr: PullRequest) {
        let content = UNMutableNotificationContent()
        content.title = "PR Updated"
        content.subtitle = pr.displayTitle
        content.body = "\(pr.repository.name) #\(pr.number)"
        content.sound = .default

        notify(
            identifier: "\(pr.id)-updated",
            content: content,
            soundName: "Glass",
            speakText: voiceAnnouncementTextPRUpdated
        )
    }

    func notifyBuildComplete(pr: PullRequest, status: BuildStatus) {
        let content = UNMutableNotificationContent()
        content.title = "\(status.icon) Build \(status.displayName)"
        content.subtitle = pr.title
        content.body = "PR #\(pr.number) in \(pr.repository.name)"
        content.sound = status == .success ? .default : .defaultCritical

        let soundName: String?
        switch status {
        case .success:
            soundName = "Glass"
        case .failure, .error:
            soundName = "Basso"
        default:
            soundName = nil
        }

        notify(
            identifier: "\(pr.id)-build",
            content: content,
            soundName: soundName,
            speakText: status == .success ? voiceAnnouncementTextBuildComplete : nil
        )
    }

    private func notify(identifier: String, content: UNMutableNotificationContent, soundName: String?, speakText: String?) {
        if notificationsEnabled {
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error showing notification: \(error.localizedDescription)")
                }
            }
        }
        if soundsEnabled, let soundName {
            play(soundNamed: soundName)
        }
        if voiceEnabled, let speakText {
            speak(text: speakText)
        }
    }


    private func play(soundNamed soundName: String) {
        if let soundURL = NSSound(named: soundName) {
            soundURL.play()
        } else if let soundPath = Bundle.main.path(forResource: soundName, ofType: "aiff") {
            let soundURL = URL(fileURLWithPath: soundPath)
            let sound = NSSound(contentsOf: soundURL, byReference: true)
            sound?.play()
        } else {
            let soundPath = "/System/Library/Sounds/\(soundName).aiff"
            if let sound = NSSound(contentsOfFile: soundPath, byReference: true) {
                sound.play()
            }
        }
    }

    private func speak(text: String) {
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = [text]

            do {
                try process.run()
            } catch {
                print("Error speaking text: \(error.localizedDescription)")
            }
        }
    }
}
