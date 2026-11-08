import XCTest
@testable import Memora

final class AnswerEvaluatorTests: XCTestCase {
    private func exercise(_ expected: String, points: [String]) -> Exercise {
        Exercise(itemID: UUID(), type: .shortAnswer, prompt: "Q", expectedAnswer: expected, keyPoints: points)
    }

    func testArabicNormalization() {
        XCTAssertEqual(TextNormalizer.normalize("أَحْمَد"), TextNormalizer.normalize("احمد"))
        XCTAssertEqual(TextNormalizer.normalize("مدرسة"), TextNormalizer.normalize("مدرسه"))
        XCTAssertEqual(TextNormalizer.normalize("مستشفى"), TextNormalizer.normalize("مستشفي"))
        XCTAssertEqual(TextNormalizer.normalize("٣٤٥"), "345")
    }

    func testArabicStemmingRemovesDefiniteArticle() {
        XCTAssertEqual(TextNormalizer.stem(TextNormalizer.normalize("الخلية")), TextNormalizer.normalize("خلية"))
    }

    func testCorrectEnglishAnswer() {
        let ex = exercise("Plants convert light energy into chemical energy", points: ["light energy", "chemical energy"])
        let result = AnswerEvaluator.evaluate(answer: "they turn light energy to chemical energy", exercise: ex)
        XCTAssertEqual(result.outcome, .correct)
        XCTAssertTrue(result.missingPoints.isEmpty)
    }

    func testPartialAnswerListsMissingPoint() {
        let ex = exercise("Plants convert light energy into chemical energy using chlorophyll",
                          points: ["light energy", "chemical energy", "chlorophyll"])
        let result = AnswerEvaluator.evaluate(answer: "uses light energy and chlorophyll", exercise: ex)
        XCTAssertEqual(result.outcome, .partial)
        XCTAssertEqual(result.missingPoints, ["chemical energy"])
    }

    func testArabicAnswerWithDiacriticsAndArticle() {
        let ex = exercise("الميتوكوندريا هي مصنع الطاقة في الخلية", points: ["مصنع الطاقة", "الخلية"])
        let result = AnswerEvaluator.evaluate(answer: "مَصْنَع طاقة خليه", exercise: ex)
        XCTAssertEqual(result.outcome, .correct)
    }

    func testDontKnow() {
        let ex = exercise("x y z", points: ["x"])
        XCTAssertEqual(AnswerEvaluator.evaluate(answer: "لا أعرف", exercise: ex).outcome, .noAnswer)
        XCTAssertEqual(AnswerEvaluator.evaluate(answer: "   ", exercise: ex).outcome, .noAnswer)
        XCTAssertEqual(AnswerEvaluator.evaluate(answer: "I don't know", exercise: ex).outcome, .noAnswer)
    }

    func testWrongAnswer() {
        let ex = exercise("The heart pumps blood", points: ["heart", "pumps blood"])
        XCTAssertEqual(AnswerEvaluator.evaluate(answer: "the lungs exchange gases", exercise: ex).outcome, .incorrect)
    }

    func testFuzzyMatchingToleratesTypos() {
        let ex = exercise("photosynthesis", points: ["photosynthesis"])
        XCTAssertEqual(AnswerEvaluator.evaluate(answer: "photosynthsis", exercise: ex).outcome, .correct)
    }

    func testMultipleChoice() {
        var ex = exercise("A", points: ["A"])
        ex.type = .multipleChoice
        ex.choices = ["B", "A", "C"]
        ex.correctChoiceIndex = 1
        XCTAssertEqual(AnswerEvaluator.evaluateChoice(selected: 1, exercise: ex).outcome, .correct)
        XCTAssertEqual(AnswerEvaluator.evaluateChoice(selected: 0, exercise: ex).outcome, .incorrect)
        XCTAssertEqual(AnswerEvaluator.evaluateChoice(selected: nil, exercise: ex).outcome, .noAnswer)
    }

    func testConfusionDetection() {
        let candidates = [(title: "Mitosis", answer: "cell division producing two identical daughter cells")]
        let confused = AnswerEvaluator.detectConfusion(answer: "division producing two identical daughter cells",
                                                       ownAnswer: "cell division producing four genetically different gametes",
                                                       candidates: candidates)
        XCTAssertEqual(confused, "Mitosis")
    }

    func testClozeHidesKeyPoint() {
        let (text, hidden) = ExerciseFactory.clozeText(answer: "Water boils at 100 degrees", preferred: ["100 degrees"])
        XCTAssertFalse(text.contains("100 degrees"))
        XCTAssertEqual(hidden, "100 degrees")
    }

    func testHintsNeverRevealFullAnswer() {
        let ex = exercise("Mitochondria produce ATP for the cell", points: ["Mitochondria", "ATP"])
        let hints = HintGenerator.hints(for: ex, item: nil)
        XCTAssertGreaterThanOrEqual(hints.count, 2)
        for hint in hints {
            XCTAssertFalse(hint.contains(ex.expectedAnswer))
        }
    }

    func testSelfGradeOverridesOutcome() {
        let base = AnswerEvaluation(outcome: .incorrect, score: 0, missingPoints: ["a"])
        let graded = AnswerEvaluator.selfGraded(base, outcome: .correct)
        XCTAssertEqual(graded.outcome, .correct)
        XCTAssertEqual(graded.source, .selfGraded)
        XCTAssertTrue(graded.missingPoints.isEmpty)
    }
}
