import Testing
import Foundation
@testable import MonitorLizard

struct BuildStatusPresentationTests {

    private static let presentations: [(status: BuildStatus, displayName: String, icon: String, systemImageName: String?)] = [
        (.conflict, "Merge Conflict", "❗", nil),
        (.notStarted, "Not started", "🛑", "play.slash"),
        (.pending, "Pending", "🔄", "gear"),
        (.success, "Success", "✅", "gear.badge.checkmark"),
        (.failure, "Failed", "❌", "gear.badge.xmark"),
        (.error, "Error", "⚠️", "gear.badge.xmark"),
        (.unknown, "Unknown", "❓", nil),
        (.inactive, "Inactive", "⏳", nil),
    ]

    @Test func buildStatusPresentationCoversEveryState() {
        #expect(Self.presentations.map(\.status) == BuildStatus.allCases)
    }

    @Test(arguments: BuildStatusPresentationTests.presentations)
    @MainActor
    func buildStatusPresentationMatchesExpected(status: BuildStatus, displayName: String, icon: String, systemImageName: String?) {
        #expect(status.displayName == displayName)
        #expect(status.icon == icon)
        #expect(status.systemImageName == systemImageName)
    }
}