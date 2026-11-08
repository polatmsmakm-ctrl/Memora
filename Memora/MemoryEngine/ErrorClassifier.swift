import Foundation

/// Facts about the surrounding situation that the classifier cannot see in the answer itself.
struct ClassificationContext: Equatable {
    /// Item was answered correctly as multiple choice within the last 14 days.
    var recognizedRecentlyByMultipleChoice: Bool = false
    /// Learner's answer matches a different item better than this one.
    var confusedWithTitle: String? = nil
    /// Prerequisites of this item that are weak, unlearned or failing.
    var weakPrerequisiteTitles: [String] = []
}

/// Deterministic rule-based classification of every incorrect, incomplete or guessed answer.
/// The order of rules is significant and documented in the README.
enum ErrorClassifier {
    static func classify(evaluation: AnswerEvaluation,
                         confidence: ConfidenceLevel?,
                         exerciseType: ExerciseType,
                         hintsUsed: Int,
                         priorFailures: Int,
                         context: ClassificationContext) -> ErrorCategory? {
        // Correct answers: only flag guesses and answers that needed heavy cueing.
        if evaluation.outcome == .correct {
            if confidence == .guess { return .guessing }
            if hintsUsed >= 2 { return .retrievalFailure }
            return nil
        }

        // 1. Repeated failure while foundations are weak → prerequisites first.
        if !context.weakPrerequisiteTitles.isEmpty && priorFailures >= 1 {
            return .missingPrerequisite
        }
        // 2. Failing to apply the concept to a new situation.
        if exerciseType.isTransfer {
            return .applicationFailure
        }
        // 3. AI judgement when available and consistent with the outcome.
        if let suggested = evaluation.suggestedCategory,
           suggested != .guessing || confidence == .guess || confidence == nil {
            return suggested
        }
        // 4. Explicit misconception statements.
        if !evaluation.misconceptions.isEmpty {
            return .misconception
        }
        // 5. Answer belongs to another concept.
        if context.confusedWithTitle != nil || evaluation.confusedWith != nil {
            return .conceptConfusion
        }
        // 6. Wrong while feeling sure.
        if evaluation.outcome == .incorrect, let confidence, confidence.isHigh {
            return .overconfidence
        }
        // 7. Recognised it as multiple choice but cannot produce it.
        if context.recognizedRecentlyByMultipleChoice && exerciseType.isRecallBased {
            return .recognitionWithoutRecall
        }
        // 8. Knowledge accessible only with cues.
        if hintsUsed > 0 && evaluation.score >= AnswerEvaluator.partialThreshold {
            return .retrievalFailure
        }
        // 9. Some elements recalled.
        if evaluation.outcome == .partial {
            return .partialRecall
        }
        // 10. Wrong answer given as a guess.
        if evaluation.outcome == .incorrect && confidence == .guess {
            return .guessing
        }
        return .completeForgetting
    }
}
