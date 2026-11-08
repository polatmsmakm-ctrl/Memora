import XCTest
@testable import Memora

final class ReminderPlannerTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    let texts = ReminderTexts(dailyTitle: "Daily", dailyBody: { "\($0) due, \($1) min" },
                              overdueTitle: "Overdue", overdueBody: { "\($0) overdue" },
                              weakTitle: "Weak", weakBody: { "\($0) weak" },
                              preSleepTitle: "Sleep", preSleepBody: { "\($0) tonight" })

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testDailyReminderUsesRealDueCountAndEstimatedMinutes() {
        let now = date(8, 9)
        let candidates = (0..<8).map { _ in ReminderCandidate(due: date(8, 15), isWeak: false) }
        let plan = ReminderPlanner.plan(now: now, candidates: candidates, reminders: ReminderSettings(), sleep: SleepSettings(),
                                        secondsPerReview: 45, calendar: calendar, texts: texts, daysAhead: 1)
        let daily = plan.first { $0.kind == .daily }
        XCTAssertNotNil(daily)
        XCTAssertEqual(daily?.count, 8)
        XCTAssertEqual(daily?.body, "8 due, 6 min")
        XCTAssertEqual(daily?.fireDate, date(8, 19))
    }

    func testNoReminderBelowMinimum() {
        let now = date(8, 9)
        let candidates = [ReminderCandidate(due: date(8, 10), isWeak: false)]
        let plan = ReminderPlanner.plan(now: now, candidates: candidates, reminders: ReminderSettings(), sleep: SleepSettings(),
                                        secondsPerReview: 40, calendar: calendar, texts: texts, daysAhead: 1)
        XCTAssertTrue(plan.filter { $0.kind == .daily }.isEmpty)
    }

    func testQuietHoursShiftReminder() {
        var settings = ReminderSettings()
        settings.dailyMinuteOfDay = 23 * 60
        settings.quietStartMinute = 22 * 60
        settings.quietEndMinute = 7 * 60
        XCTAssertTrue(ReminderPlanner.isQuiet(minute: 23 * 60, reminders: settings, sleep: SleepSettings()))
        XCTAssertTrue(ReminderPlanner.isQuiet(minute: 3 * 60, reminders: settings, sleep: SleepSettings()))
        XCTAssertFalse(ReminderPlanner.isQuiet(minute: 12 * 60, reminders: settings, sleep: SleepSettings()))
        let adjusted = ReminderPlanner.adjustedForQuiet(date(8, 23), reminders: settings, sleep: SleepSettings(), calendar: calendar)
        XCTAssertEqual(adjusted, date(9, 7))
    }

    func testFrequencyCapLimitsPerDay() {
        var settings = ReminderSettings()
        settings.frequency = .low
        let now = date(8, 9)
        let candidates = (0..<10).map { _ in ReminderCandidate(due: date(1, 9), isWeak: true) }
        let plan = ReminderPlanner.plan(now: now, candidates: candidates, reminders: settings, sleep: SleepSettings(),
                                        secondsPerReview: 40, calendar: calendar, texts: texts, daysAhead: 3)
        let byDay = Dictionary(grouping: plan) { calendar.startOfDay(for: $0.fireDate) }
        XCTAssertTrue(byDay.values.allSatisfy { $0.count <= 1 })
        XCTAssertTrue(plan.contains { $0.kind == .daily })
    }

    func testDisabledRemindersPlanNothing() {
        var settings = ReminderSettings()
        settings.enabled = false
        let plan = ReminderPlanner.plan(now: date(8, 9), candidates: [ReminderCandidate(due: date(8, 9), isWeak: false)],
                                        reminders: settings, sleep: SleepSettings(), secondsPerReview: 40, calendar: calendar, texts: texts)
        XCTAssertTrue(plan.isEmpty)
    }

    func testSleepWindowIsQuiet() {
        var sleep = SleepSettings()
        sleep.enabled = true
        sleep.bedtimeMinute = 23 * 60
        sleep.wakeMinute = 6 * 60
        var reminders = ReminderSettings()
        reminders.quietHoursEnabled = false
        XCTAssertTrue(ReminderPlanner.isQuiet(minute: 1 * 60, reminders: reminders, sleep: sleep))
        XCTAssertFalse(ReminderPlanner.isQuiet(minute: 20 * 60, reminders: reminders, sleep: sleep))
    }
}
