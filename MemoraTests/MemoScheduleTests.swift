import XCTest
@testable import Memora

final class MemoScheduleTests: XCTestCase {
    private func makeItem() -> LearningItem {
        LearningItem(subjectID: UUID(), kind: .concept, title: "قسمة الكسور", prompt: "وش القاعدة؟", answer: "مقام المقام يصعد وينضرب")
    }

    func testFullScheduleEndsMastered() {
        var item = makeItem()
        var now = Date(timeIntervalSince1970: 1_000_000)
        MemoSchedule.start(&item, kind: .rule, now: now)
        XCTAssertTrue(item.isIntroduced)
        XCTAssertEqual(item.card.due, now.addingTimeInterval(3_600))
        let expected: [TimeInterval] = [86_400, 3 * 86_400, 7 * 86_400, 10.5 * 86_400]
        for interval in expected {
            now = item.card.due
            XCTAssertTrue(MemoSchedule.isDue(item, now: now))
            XCTAssertFalse(MemoSchedule.review(&item, remembered: true, now: now))
            XCTAssertEqual(item.card.due, now.addingTimeInterval(interval))
        }
        now = item.card.due
        XCTAssertTrue(MemoSchedule.review(&item, remembered: true, now: now))
        XCTAssertNotNil(item.masteredAt)
        XCTAssertFalse(MemoSchedule.isActive(item))
        XCTAssertEqual(MemoSchedule.progress(item), 5)
        XCTAssertEqual(MemoSchedule.masteredLabel(kind: item.memoKind), L("memo.mastered.rule"))
    }

    func testForgettingGoesBackOneStep() {
        var item = makeItem()
        let now = Date(timeIntervalSince1970: 1_000_000)
        MemoSchedule.start(&item, now: now)
        MemoSchedule.review(&item, remembered: true, now: now) // step 1 (1 day)
        MemoSchedule.review(&item, remembered: true, now: now) // step 2 (3 days)
        MemoSchedule.review(&item, remembered: false, now: now)
        XCTAssertEqual(item.memoStep, 1)
        XCTAssertEqual(item.card.due, now.addingTimeInterval(86_400))
    }

    func testLocalWordsParse() {
        let cards = LocalCards.wordCards(from: "apple - تفاحة\nbook: كتاب\n\nhouse")
        XCTAssertEqual(cards.map(\.front), ["apple", "book", "house"])
        XCTAssertEqual(cards[0].back, "تفاحة")
        XCTAssertEqual(cards[1].back, "كتاب")
    }

    func testLocalRuleKeepsTextExactly() {
        let set = LocalCards.build(type: .rule, title: "قسمة الكسور", text: "مقام المقام يصعد وينضرب")
        XCTAssertEqual(set.cards.count, 1)
        XCTAssertEqual(set.cards[0].back, "مقام المقام يصعد وينضرب")
        XCTAssertEqual(set.type, .rule)
    }
}
