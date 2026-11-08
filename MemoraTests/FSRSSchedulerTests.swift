import XCTest
@testable import Memora

final class FSRSSchedulerTests: XCTestCase {
    let scheduler = FSRSScheduler()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testRetrievabilityEqualsNinetyPercentAtStability() {
        let r = scheduler.retrievability(stability: 10, elapsedDays: 10)
        XCTAssertEqual(r, 0.9, accuracy: 1e-9)
        XCTAssertEqual(scheduler.retrievability(stability: 10, elapsedDays: 0), 1, accuracy: 1e-12)
    }

    func testIntervalMatchesStabilityAtNinetyPercent() {
        XCTAssertEqual(scheduler.intervalDays(for: 10, desiredRetention: 0.9), 10)
        XCTAssertEqual(scheduler.intervalDays(for: 37.2, desiredRetention: 0.9), 37)
    }

    func testHigherDesiredRetentionShortensInterval() {
        let low = scheduler.intervalDays(for: 30, desiredRetention: 0.8)
        let high = scheduler.intervalDays(for: 30, desiredRetention: 0.95)
        XCTAssertGreaterThan(low, high)
    }

    func testNewCardGoodEntersSecondLearningStep() {
        let outcome = scheduler.review(FSRSCard(due: t0), rating: .good, at: t0)
        XCTAssertEqual(outcome.card.state, .learning)
        XCTAssertEqual(outcome.card.step, 1)
        XCTAssertEqual(outcome.interval, 600, accuracy: 0.001)
        XCTAssertEqual(outcome.card.stability, FSRSParameters.defaultWeights[2], accuracy: 1e-9)
        XCTAssertEqual(outcome.card.reps, 1)
    }

    func testNewCardEasyGraduatesImmediately() {
        let outcome = scheduler.review(FSRSCard(due: t0), rating: .easy, at: t0)
        XCTAssertEqual(outcome.card.state, .review)
        XCTAssertGreaterThanOrEqual(outcome.scheduledDays, 1)
    }

    func testLearningGoodTwiceGraduatesToReview() {
        var card = scheduler.review(FSRSCard(due: t0), rating: .good, at: t0).card
        let second = scheduler.review(card, rating: .good, at: t0.addingTimeInterval(600))
        card = second.card
        XCTAssertEqual(card.state, .review)
        XCTAssertGreaterThanOrEqual(second.scheduledDays, 1)
    }

    func testAgainInReviewGoesToRelearningAndCountsLapse() {
        var card = scheduler.review(FSRSCard(due: t0), rating: .easy, at: t0).card
        let reviewTime = card.due
        let lapse = scheduler.review(card, rating: .again, at: reviewTime)
        card = lapse.card
        XCTAssertEqual(card.state, .relearning)
        XCTAssertEqual(card.lapses, 1)
        XCTAssertEqual(lapse.interval, 600, accuracy: 0.001)
        let recovered = scheduler.review(card, rating: .good, at: reviewTime.addingTimeInterval(600))
        XCTAssertEqual(recovered.card.state, .review)
    }

    func testSuccessfulReviewIncreasesStability() {
        let first = scheduler.review(FSRSCard(due: t0), rating: .easy, at: t0).card
        let next = scheduler.review(first, rating: .good, at: first.due)
        XCTAssertGreaterThan(next.card.stability, first.stability)
        XCTAssertGreaterThan(next.scheduledDays, 1)
    }

    func testForgettingReducesStability() {
        let first = scheduler.review(FSRSCard(due: t0), rating: .easy, at: t0).card
        let later = scheduler.review(first, rating: .good, at: first.due).card
        let forgot = scheduler.review(later, rating: .again, at: later.due)
        XCTAssertLessThan(forgot.card.stability, later.stability)
    }

    func testDifficultyStaysWithinBounds() {
        var card = FSRSCard(due: t0)
        var now = t0
        for _ in 0..<30 {
            card = scheduler.review(card, rating: .again, at: now).card
            now = now.addingTimeInterval(86_400 * 2)
        }
        XCTAssertLessThanOrEqual(card.difficulty, 10)
        XCTAssertGreaterThanOrEqual(card.difficulty, 1)
        for _ in 0..<30 {
            card = scheduler.review(card, rating: .easy, at: now).card
            now = card.due
        }
        XCTAssertGreaterThanOrEqual(card.difficulty, 1)
    }

    func testHardIsBetweenAgainAndGoodForReviewCard() {
        let first = scheduler.review(FSRSCard(due: t0), rating: .easy, at: t0).card
        let preview = scheduler.preview(first, at: first.due)
        XCTAssertLessThan(preview[.again]!, preview[.hard]!)
        XCTAssertLessThanOrEqual(preview[.hard]!, preview[.good]!)
        XCTAssertLessThanOrEqual(preview[.good]!, preview[.easy]!)
    }

    func testSchedulingIsDeterministic() {
        let a = scheduler.review(FSRSCard(due: t0), rating: .good, at: t0)
        let b = scheduler.review(FSRSCard(due: t0), rating: .good, at: t0)
        XCTAssertEqual(a, b)
    }

    func testInvalidWeightsFallBackToDefaults() {
        var params = FSRSParameters()
        params.weights = [1, 2, 3]
        let custom = FSRSScheduler(parameters: params)
        let outcome = custom.review(FSRSCard(due: t0), rating: .good, at: t0)
        XCTAssertEqual(outcome.card.stability, FSRSParameters.defaultWeights[2], accuracy: 1e-9)
    }

    func testParseWeights() {
        let text = FSRSParameters.defaultWeights.map { String($0) }.joined(separator: ", ")
        XCTAssertEqual(FSRSParameters.parseWeights(text)?.count, 19)
        XCTAssertNil(FSRSParameters.parseWeights("1, 2, 3"))
        XCTAssertNil(FSRSParameters.parseWeights(text + ", abc"))
    }

    func testNewCardHasZeroRetrievability() {
        XCTAssertEqual(scheduler.retrievability(of: FSRSCard(due: t0), at: t0), 0)
        XCTAssertFalse(scheduler.isDue(FSRSCard(due: t0), at: t0))
    }
}
