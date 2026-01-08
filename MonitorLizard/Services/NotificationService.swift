import Foundation
import UserNotifications
import AppKit
import AVFoundation

class NotificationService {
    static let shared = NotificationService()

    private var soundsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "enableSounds")
    }

    private var voiceEnabled: Bool {
        UserDefaults.standard.bool(forKey: "enableVoice")
    }

    private var notificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "showNotifications")
    }

    private var voiceAnnouncementText: String {
        UserDefaults.standard.string(forKey: "voiceAnnouncementText") ?? "Build ready for Q A"
    }

    private init() {
        // Set default values
        if UserDefaults.standard.object(forKey: "enableSounds") == nil {
            UserDefaults.standard.set(true, forKey: "enableSounds")
        }
        if UserDefaults.standard.object(forKey: "enableVoice") == nil {
            UserDefaults.standard.set(true, forKey: "enableVoice")
        }
        if UserDefaults.standard.object(forKey: "showNotifications") == nil {
            UserDefaults.standard.set(true, forKey: "showNotifications")
        }
        if UserDefaults.standard.object(forKey: "voiceAnnouncementText") == nil {
            UserDefaults.standard.set("Build ready for Q A", forKey: "voiceAnnouncementText")
        }
    }

    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func notifyBuildComplete(pr: PullRequest, status: BuildStatus) {
        // Show notification
        if notificationsEnabled {
            showNotification(pr: pr, status: status)
        }

        // Play sound
        if soundsEnabled {
            playSound(for: status)
        }

        // Speak announcement
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

        // Play system sound
        if let soundURL = NSSound(named: soundName) {
            soundURL.play()
        } else if let soundPath = Bundle.main.path(forResource: soundName, ofType: "aiff") {
            let soundURL = URL(fileURLWithPath: soundPath)
            let sound = NSSound(contentsOf: soundURL, byReference: true)
            sound?.play()
        } else {
            // Fallback to system sound path
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
