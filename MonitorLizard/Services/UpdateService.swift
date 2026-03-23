import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
final class UpdateService {
    static let shared = UpdateService()

    private let delegate = UpdaterDelegate()
    private let updaterController: SPUStandardUpdaterController

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )

        let updater = updaterController.updater
        updater.updateCheckInterval = 86400 // 24 hours
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = true
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        // SUNoUpdateAvailableError (1001) is informational — Sparkle already showed its own dialog
        guard nsError.code != 1001 else { return }

        print("[UpdateService] Updater aborted: \(nsError.domain) \(nsError.code) — \(nsError.localizedDescription)")
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            print("[UpdateService] Underlying error: \(underlying.domain) \(underlying.code) — \(underlying.localizedDescription)")
        }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Update Failed"
            alert.informativeText = nsError.localizedDescription
            if let recovery = nsError.localizedRecoverySuggestion {
                alert.informativeText += "\n\n" + recovery
            }
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                alert.informativeText += "\n\nUnderlying error (\(underlying.domain) \(underlying.code)): \(underlying.localizedDescription)"
            }
            alert.runModal()
        }
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        let nsError = error as NSError
        print("[UpdateService] Download failed for \(item.displayVersionString): \(nsError.domain) \(nsError.code) — \(nsError.localizedDescription)")
    }
}
