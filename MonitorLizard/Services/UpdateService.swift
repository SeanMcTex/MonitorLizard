import Combine
import Foundation
import Sparkle

@MainActor
final class UpdateService {
    static let shared = UpdateService()

    private let updaterController: SPUStandardUpdaterController

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
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
