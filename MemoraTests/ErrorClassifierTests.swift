import XCTest
@testable import Memora

final class ErrorClassifierTests: XCTestCase {
    private func classify(_ outcome: Outcome, score: Double? = nil, confidence: ConfidenceLevel? = .unsure,
                          type: ExerciseType = .shortAnswer, hints: Int = 0, priorFailures: Int = 0,
                          context: ClassificationContext = ClassificationContext(),
                          misconceptions: [String] = [], suggested: ErrorCategory? = nil) -> ErrorCategory? {
        var evaluation = AnswerEvaluation(outcome: outcome, score: score ?? outcome.score)
        evaluation.misconceptions = misconceptions
        evaluation.suggestedCategory = suggested
        return ErrorClassifier.classify(evaluation: evaluation, confidence: confidence, exerciseType: type,
                                        hintsUsed: hints, priorFailures: priorFailures, context: context)
    }

    func testCorrectAnswersHaveNoCategory() {
        XCTAssertNil(classify(.correct, confidence: .certain))
    }

    func testCorrectGuessIsGuessing() {
        XCTAssertEqual(classify(.correct, confidence: .guess), .guessing)
    }

    func testCorrectWithManyHintsIsRetrievalFailure() {
        XCTAssertEqual(classify(.correct, confidence: .fairly, hints: 2), .retrievalFailure)
    }

    func testNoAnswerIsCompleteForgetting() {
        XCTAssertEqual(classify(.noAnswer, confidence: .unsure), .completeForgetting)
    }

    func testPartial() {
        XCTAssertEqual(classify(.partial, score: 0.5), .partialRecall)
    }

    func testMisconception() {
        XCTAssertEqual(classify(.incorrect, misconceptions: ["Plants eat soil"]), .misconception)
    }

    func testConceptConfusion() {
        XCTAssertEqual(classify(.incorrect, context: ClassificationContext(confusedWithTitle: "Mitosis")), .conceptConfusion)
    }

    func testOverconfidence() {
        XCTAssertEqual(classify(.incorrect, confidence: .certain), .overconfidence)
    }

    func testRecognitionWithoutRecall() {
        let context = ClassificationContext(recognizedRecentlyByMultipleChoice: true)
        XCTAssertEqual(classify(.noAnswer, confidence: .unsure, type: .freeRecall, context: context), .recognitionWithoutRecall)
    }

    func testRetrievalFailureWithHintsAndPartialContent() {
        XCTAssertEqual(classify(.partial, score: 0.6, hints: 1), .retrievalFailure)
    }

    func testIncorrectGuess() {
        XCTAssertEqual(classify(.incorrect, confidence: .guess), .guessing)
    }

    func testApplicationFailureOnTransfer() {
        XCTAssertEqual(classify(.incorrect, type: .transferNear), .applicationFailure)
        XCTAssertEqual(classify(.partial, type: .transferFar), .applicationFailure)
    }

    func testMissingPrerequisiteNeedsRepeatedFailure() {
        let context = ClassificationContext(weakPrerequisiteTitles: ["Cell"])
        XCTAssertEqual(classify(.incorrect, priorFailures: 1, context: context), .missingPrerequisite)
        XCTAssertNotEqual(classify(.incorrect, priorFailures: 0, context: context), .missingPrerequisite)
    }

    func testAISuggestionUsedWhenConsistent() {
        XCTAssertEqual(classify(.incorrect, suggested: .conceptConfusion), .conceptConfusion)
    }

    func testEachCategoryGetsDistinctIntervention() {
        let kinds = ErrorCategory.allCases.map {
            InterventionPlanner.plan(for: $0, evaluation: AnswerEvaluation(outcome: .incorrect, score: 0), context: ClassificationContext()).kind
        }
        XCTAssertEqual(Set(kinds).count, ErrorCategory.allCases.count)
    }

    func testPartialRecallFocusesOnMissingPoints() {
        var evaluation = AnswerEvaluation(outcome: .partial, score: 0.5)
        evaluation.missingPoints = ["chlorophyll"]
        let plan = InterventionPlanner.plan(for: .partialRecall, evaluation: evaluation, context: ClassificationContext())
        XCTAssertEqual(plan.followUpType, .cloze)
        XCTAssertEqual(plan.focusPoints, ["chlorophyll"])
    }
}
