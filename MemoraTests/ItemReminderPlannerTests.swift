import XCTest
@testable import Memora

final class ItemReminderPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour, minute: minute))!
    }

    func testQuietHoursMoveToMorning() {
        let late = ItemReminderPlanner.outsideQuietHours(date(23), start: 22 * 60, end: 8 * 60, calendar: calendar)
        XCTAssertEqual(late, date(8, day: 2))
        let early = ItemReminderPlanner.outsideQuietHours(date(3), start: 22 * 60, end: 8 * 60, calendar: calendar)
        XCTAssertEqual(early, date(8))
        let day = ItemReminderPlanner.outsideQuietHours(date(14), start: 22 * 60, end: 8 * 60, calendar: calendar)
        XCTAssertEqual(day, date(14))
    }

    func testCloseCardsShareANotificationAndPastOnesAreSkipped() {
        let now = date(10)
        let cards = [
            ItemReminderPlanner.Card(id: UUID(), due: date(9), cue: "past", subject: ""),
            ItemReminderPlanner.Card(id: UUID(), due: date(12), cue: "a", subject: ""),
            ItemReminderPlanner.Card(id: UUID(), due: date(12, 10), cue: "b", subject: ""),
            ItemReminderPlanner.Card(id: UUID(), due: date(16), cue: "c", subject: ""),
        ]
        let plan = ItemReminderPlanner.plan(now: now, cards: cards, quietStart: nil, quietEnd: nil, calendar: calendar)
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan[0].cards.map(\.cue), ["a", "b"])
        XCTAssertEqual(plan[1].cards.map(\.cue), ["c"])
    }
}
