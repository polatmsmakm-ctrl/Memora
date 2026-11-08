import Foundation

/// Rubric for explanation-type answers (self-explanation, elaboration).
struct RubricScores: Codable, Hashable {
    var accuracy: Double
    var completeness: Double
    var logic: Double
    var depth: Double
}

/// Result of grading one retrieval attempt.
struct AnswerEvaluation: Codable, Hashable {
    var outcome: Outcome
    var score: Double
    var matchedPoints: [String] = []
    var missingPoints: [String] = []
    var incorrectStatements: [String] = []
    var misconceptions: [String] = []
    var feedback: String = ""
    var source: EvaluationSource = .local
    var suggestedCategory: ErrorCategory? = nil
    var confusedWith: String? = nil
    var rubric: RubricScores? = nil
}

/// Offline grader. Works without any network and is the fallback whenever AI is
/// unavailable. It checks key-point coverage with Arabic/English normalisation.
enum AnswerEvaluator {
    static let correctThreshold = 0.8
    static let partialThreshold = 0.4
    static let pointMatchRatio = 0.6

    static let dontKnowPhrases: [String] = [
        "لا اعرف", "لا ادري", "ما اعرف", "مدري", "ما ادري", "نسيت", "لا اتذكر",
        "i dont know", "i don t know", "dont know", "no idea", "idk", "forgot", "i forgot", "not sure"
    ]

    static func isDontKnow(_ text: String) -> Bool {
        let n = TextNormalizer.normalize(text)
        if n.isEmpty || n == "?" { return true }
        return dontKnowPhrases.contains { n == TextNormalizer.normalize($0) }
    }

    static func evaluate(answer: String, exercise: Exercise) -> AnswerEvaluation {
        if isDontKnow(answer) {
            return AnswerEvaluation(outcome: .noAnswer, score: 0,
                                    missingPoints: exercise.keyPoints,
                                    feedback: L("feedback.noAnswer"))
        }
        let result = coverage(of: answer, keyPoints: exercise.keyPoints, expected: exercise.expectedAnswer)
        let outcome: Outcome
        if result.score >= correctThreshold {
            outcome = .correct
        } else if result.score >= partialThreshold {
            outcome = .partial
        } else {
            outcome = .incorrect
        }
        return AnswerEvaluation(outcome: outcome,
                                score: result.score,
                                matchedPoints: result.matched,
                                missingPoints: result.missing,
                                feedback: feedback(for: outcome, missing: result.missing))
    }

    static func evaluateChoice(selected: Int?, exercise: Exercise) -> AnswerEvaluation {
        guard let selected else {
            return AnswerEvaluation(outcome: .noAnswer, score: 0, feedback: L("feedback.noAnswer"))
        }
        let correct = selected == exercise.correctChoiceIndex
        let chosen = exercise.choices.indices.contains(selected) ? exercise.choices[selected] : ""
        return AnswerEvaluation(outcome: correct ? .correct : .incorrect,
                                score: correct ? 1 : 0,
                                matchedPoints: correct ? [exercise.expectedAnswer] : [],
                                missingPoints: correct ? [] : [exercise.expectedAnswer],
                                incorrectStatements: correct ? [] : [chosen],
                                feedback: correct ? L("feedback.correct") : L("feedback.choiceWrong"))
    }

    /// Key-point coverage. Each key point counts as matched when ≥60% of its content
    /// tokens appear (fuzzily) in the answer.
    static func coverage(of answer: String, keyPoints: [String], expected: String) -> (score: Double, matched: [String], missing: [String]) {
        let answerTokens = Set(TextNormalizer.contentTokens(answer))
        guard !answerTokens.isEmpty else { return (0, [], keyPoints) }

        let points = keyPoints.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if points.isEmpty {
            let expectedTokens = Array(Set(TextNormalizer.contentTokens(expected)))
            guard !expectedTokens.isEmpty else { return (0, [], []) }
            let found = expectedTokens.filter { contains(answerTokens, $0) }
            let missing = expectedTokens.filter { !contains(answerTokens, $0) }
            return (Double(found.count) / Double(expectedTokens.count), found, Array(missing.prefix(6)))
        }

        var matched: [String] = []
        var missing: [String] = []
        for point in points {
            let tokens = TextNormalizer.contentTokens(point)
            guard !tokens.isEmpty else { continue }
            let hits = tokens.filter { contains(answerTokens, $0) }.count
            if Double(hits) / Double(tokens.count) >= pointMatchRatio {
                matched.append(point)
            } else {
                missing.append(point)
            }
        }
        let total = matched.count + missing.count
        return (total == 0 ? 0 : Double(matched.count) / Double(total), matched, missing)
    }

    private static func contains(_ set: Set<String>, _ token: String) -> Bool {
        set.contains(token) || set.contains { TextNormalizer.fuzzyEqual($0, token) }
    }

    /// Detects when the learner produced another item's answer (concept confusion).
    static func detectConfusion(answer: String, ownAnswer: String, candidates: [(title: String, answer: String)]) -> String? {
        guard !isDontKnow(answer) else { return nil }
        let own = TextNormalizer.coverage(of: ownAnswer, in: answer)
        var best: (title: String, score: Double)?
        for candidate in candidates {
            let score = TextNormalizer.coverage(of: candidate.answer, in: answer)
            if score >= 0.6, score > own + 0.2, score > (best?.score ?? 0) {
                best = (candidate.title, score)
            }
        }
        return best?.title
    }

    static func feedback(for outcome: Outcome, missing: [String]) -> String {
        switch outcome {
        case .correct:
            return L("feedback.correct")
        case .partial:
            return missing.isEmpty ? L("feedback.partial") : LF("feedback.partialMissing", missing.prefix(4).joined(separator: "، "))
        case .incorrect:
            return L("feedback.incorrect")
        case .noAnswer:
            return L("feedback.noAnswer")
        }
    }

    /// Re-labels an evaluation after the learner self-grades it.
    static func selfGraded(_ evaluation: AnswerEvaluation, outcome: Outcome) -> AnswerEvaluation {
        var e = evaluation
        e.outcome = outcome
        e.score = outcome.score
        e.source = .selfGraded
        if outcome == .correct {
            e.missingPoints = []
            e.misconceptions = []
            e.incorrectStatements = []
            e.suggestedCategory = nil
            e.confusedWith = nil
        }
        return e
    }
}
