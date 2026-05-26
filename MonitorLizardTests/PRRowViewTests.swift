import Testing
import Foundation
@testable import MonitorLizard

struct DaysSinceUpdateTests {

    // Fixed "now": 2024-01-15 09:00 local time.
    private let now = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 15, hour: 9))!

    private func date(daysAgo: Int, hour: Int = 9, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 15 - daysAgo, hour: hour, minute: minute))!
    }

    @Test func updatedTodayReturnsZero() {
        #expect(PRRowView.daysSinceUpdate(from: date(daysAgo: 0), now: now) == 0)
    }

    @Test func updatedJustAfterMidnightTodayReturnsZero() {
        #expect(PRRowView.daysSinceUpdate(from: date(daysAgo: 0, hour: 0, minute: 1), now: now) == 0)
    }

    @Test func updatedLateLastNightReturnsOne() {
        // Regression: 23:53 the previous calendar day was previously reported as "today".
        #expect(PRRowView.daysSinceUpdate(from: date(daysAgo: 1, hour: 23, minute: 53), now: now) == 1)
    }

    @Test func updatedYesterdayReturnsOne() {
        #expect(PRRowView.daysSinceUpdate(from: date(daysAgo: 1), now: now) == 1)
    }

    @Test func updatedTwoDaysAgoReturnsTwo() {
        #expect(PRRowView.daysSinceUpdate(from: date(daysAgo: 2), now: now) == 2)
    }
}
