import AppKit
import AVFoundation
import Dependencies
import Foundation
import UserNotifications

/// Posts system notifications, plays sounds, and speaks announcements for build completions.
///
/// - Important: This type is `@unchecked Sendable` because all mutable state is accessed
///   exclusively from the main thread. Calling from a background thread will trigger an
///   assertion failure in debug builds.
final class NotificationService: @unchecked Sendable {
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

    private var voiceAnnouncementText: String {
        assertMainThread()
        return defaults.string(forKey: PreferenceKeys.voiceAnnouncementText) ?? Constants.defaultVoiceAnnouncementText
    }

    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func notifyBuildComplete(pr: PullRequest, status: BuildStatus) {
        if notificationsEnabled {
            showNotification(pr: pr, status: status)
        }

        if soundsEnabled {
            playSound(for: status)
        }

        if voiceEnabled && status == .success {
            speak(text: voiceAnnouncementText)
        }
    }

    private func showNotification(pr: PullRequest, status: BuildStatus) {
        let content = UNMutableNotificationContent()
        content.title = "\(status.icon) Build \(status.displayName)"
        content.subtitle = pr.title
        content.body = "PR #\(pr.number) in \(pr.repository.name)"
        content.sound = status == .success ? .default : .defaultCritical

        let request = UNNotificationRequest(
            identifier: pr.id,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing notification: \(error.localizedDescription)")
            }
        }
    }

    private func playSound(for status: BuildStatus) {
        let soundName: String

        switch status {
        case .success:
            soundName = "Glass"
        case .failure, .error:
            soundName = "Basso"
        default:
            return
        }

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
