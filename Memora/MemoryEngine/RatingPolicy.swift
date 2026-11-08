import Foundation

/// Maps a graded attempt to an FSRS rating. This is the only bridge between the
/// learning-state layer and FSRS: everything else (confidence, error types, hints)
/// is used only for classification and interventions, never inside FSRS formulas.
enum RatingPolicy {
    static let easyMaxSeconds: Double = 20

    static func suggestedRating(evaluation: AnswerEvaluation,
                                confidence: ConfidenceLevel?,
                                hintsUsed: Int,
                                exerciseType: ExerciseType,
                                responseSeconds: Double) -> Rating {
        switch evaluation.outcome {
        case .noAnswer, .incorrect:
            return .again
        case .partial:
            return .hard
        case .correct:
            if hintsUsed > 0 || confidence == .guess { return .hard }
            if exerciseType == .multipleChoice { return .good } // recognition is easier than recall
            if confidence == .certain && evaluation.score >= 0.95 && responseSeconds <= easyMaxSeconds {
                return .easy
            }
            return .good
        }
    }
}
