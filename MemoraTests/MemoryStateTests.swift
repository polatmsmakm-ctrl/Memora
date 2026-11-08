import XCTest
@testable import Memora

final class MemoryStateTests: XCTestCase {
    let scheduler = FSRSScheduler()
    let subject = UUID()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func item() -> LearningItem {
        LearningItem(subjectID: subject, title: "Photosynthesis", prompt: "What is photosynthesis?",
                     answer: "Plants convert light energy into chemical energy", keyPoints: ["light energy", "chemical energy"],
                     createdAt: t0)
    }

    private func attempt(_ item: LearningItem, outcome: Outcome, at date: Date, rating: Rating? = nil) -> LearningItem {
        let evaluation = AnswerEvaluation(outcome: outcome, score: outcome.score)
        let input = AttemptInput(exerciseType: .shortAnswer, evaluation: evaluation, confidence: .fairly, hintsUsed: 0,
                                 responseSeconds: 10, userAnswer: "", mode: .remember, sessionID: UUID(), variantIndex: nil,
                                 overrideRating: rating, countsForScheduling: true, date: date)
        return ReviewProcessor.process(item: item, input: input, context: ClassificationContext(), scheduler: scheduler, calendar: calendar).item
    }

    func testUnseenAndNew() {
        var i = item()
        XCTAssertEqual(MemoryStateClassifier.state(of: i, scheduler: scheduler, now: t0), .unseen)
        i.introducedAt = t0
        XCTAssertEqual(MemoryStateClassifier.state(of: i, scheduler: scheduler, now: t0), .new)
    }

    func testFirstCorrectAttemptIsLearningNotMastered() {
        let i = attempt(item(), outcome: .correct, at: t0)
        XCTAssertEqual(MemoryStateClassifier.state(of: i, scheduler: scheduler, now: t0), .learning)
        XCTAssertFalse(MemoryStateClassifier.isMastered(i))
        XCTAssertNotNil(i.introducedAt)
    }

    func testOneSuccessIsNeverLongTerm() {
        var i = attempt(item(), outcome: .correct, at: t0, rating: .easy)
        i.card.stability = 100
        XCTAssertNotEqual(MemoryStateClassifier.state(of: i, scheduler: scheduler, now: t0.addingTimeInterval(3600)), .longTerm)
    }

    func testSuccessiveRelearningReachesLongTermAndFailureRevokesIt() {
        var i = attempt(item(), outcome: .correct, at: t0, rating: .easy)
        var now = t0
        for _ in 0..<4 {
            now = i.card.due
            i = attempt(i, outcome: .correct, at: now, rating: .easy)
        }
        XCTAssertGreaterThanOrEqual(i.profile.distinctSuccessfulDays, 3)
        if i.card.stability < MemoryStateClassifier.longTermStabilityDays {
            i.card.stability = 30
        }
        XCTAssertTrue(MemoryStateClassifier.isMastered(i))
        XCTAssertEqual(MemoryStateClassifier.state(of: i, scheduler: scheduler, now: now.addingTimeInterval(3600)), .longTerm)

        let failed = attempt(i, outcome: .incorrect, at: i.card.due)
        XCTAssertFalse(MemoryStateClassifier.isMastered(failed))
        XCTAssertEqual(failed.profile.distinctSuccessfulDays, 0)
        XCTAssertNotNil(failed.profile.masteryRevokedAt)
        XCTAssertEqual(MemoryStateClassifier.state(of: failed, scheduler: scheduler, now: i.card.due), .relearning)
    }

    func testWeakWhenRetrievabilityLow() {
        var i = attempt(item(), outcome: .correct, at: t0, rating: .easy)
        XCTAssertEqual(i.card.state, .review)
        let farFuture = t0.addingTimeInterval(86_400 * 400)
        XCTAssertEqual(MemoryStateClassifier.state(of: i, scheduler: scheduler, now: farFuture), .weak)
        i.profile.lastOutcomes = [.incorrect, .noAnswer]
        XCTAssertEqual(MemoryStateClassifier.state(of: i, scheduler: scheduler, now: t0.addingTimeInterval(60)), .weak)
    }

    func testProfileCountsAreSeparatedFromFSRS() {
        var i = attempt(item(), outcome: .correct, at: t0)
        i = attempt(i, outcome: .partial, at: t0.addingTimeInterval(600))
        i = attempt(i, outcome: .incorrect, at: t0.addingTimeInterval(1200))
        XCTAssertEqual(i.profile.successCount, 1)
        XCTAssertEqual(i.profile.partialCount, 1)
        XCTAssertEqual(i.profile.failureCount, 1)
        XCTAssertEqual(i.card.reps, 3)
        XCTAssertEqual(i.profile.confidenceHistory.count, 3)
    }

    func testPretestDoesNotTouchScheduling() {
        let evaluation = AnswerEvaluation(outcome: .incorrect, score: 0)
        let input = AttemptInput(exerciseType: .shortAnswer, evaluation: evaluation, confidence: .guess, hintsUsed: 0,
                                 responseSeconds: 5, userAnswer: "x", mode: .pretest, sessionID: UUID(), variantIndex: nil,
                                 overrideRating: nil, countsForScheduling: false, date: t0)
        let result = ReviewProcessor.process(item: item(), input: input, context: ClassificationContext(), scheduler: scheduler)
        XCTAssertEqual(result.item.card.state, .new)
        XCTAssertEqual(result.item.profile.failureCount, 0)
        XCTAssertNotNil(result.item.pretestedAt)
        XCTAssertNil(result.log.rating)
        XCTAssertFalse(result.log.countedForScheduling)
    }

    func testRatingPolicy() {
        let correct = AnswerEvaluation(outcome: .correct, score: 1)
        XCTAssertEqual(RatingPolicy.suggestedRating(evaluation: correct, confidence: .certain, hintsUsed: 0, exerciseType: .freeRecall, responseSeconds: 5), .easy)
        XCTAssertEqual(RatingPolicy.suggestedRating(evaluation: correct, confidence: .fairly, hintsUsed: 0, exerciseType: .freeRecall, responseSeconds: 5), .good)
        XCTAssertEqual(RatingPolicy.suggestedRating(evaluation: correct, confidence: .certain, hintsUsed: 1, exerciseType: .freeRecall, responseSeconds: 5), .hard)
        XCTAssertEqual(RatingPolicy.suggestedRating(evaluation: correct, confidence: .guess, hintsUsed: 0, exerciseType: .freeRecall, responseSeconds: 5), .hard)
        XCTAssertEqual(RatingPolicy.suggestedRating(evaluation: correct, confidence: .certain, hintsUsed: 0, exerciseType: .multipleChoice, responseSeconds: 5), .good)
        XCTAssertEqual(RatingPolicy.suggestedRating(evaluation: AnswerEvaluation(outcome: .partial, score: 0.5), confidence: nil, hintsUsed: 0, exerciseType: .cloze, responseSeconds: 5), .hard)
        XCTAssertEqual(RatingPolicy.suggestedRating(evaluation: AnswerEvaluation(outcome: .noAnswer, score: 0), confidence: nil, hintsUsed: 0, exerciseType: .cloze, responseSeconds: 5), .again)
    }
}
