import Foundation

enum InterventionKind: String, Codable {
    case relearnAndRetest, focusMissing, compareConcepts, correctMisconception
    case cuedThenBlindRecall, blindRecall, confidenceRecheck, transferPractice
    case calibrationNotice, reviewPrerequisites

    var title: String { L("intervention.\(rawValue)") }
}

/// A targeted next step chosen for a specific error type.
struct Intervention: Equatable {
    var kind: InterventionKind
    /// Follow-up retrieval inserted later in the same session (another retrieval opportunity).
    var followUpType: ExerciseType?
    var showExplanation: Bool
    var focusPoints: [String]
    var comparisonTitle: String?
    var prerequisiteTitles: [String]
}

enum InterventionPlanner {
    static func plan(for category: ErrorCategory, evaluation: AnswerEvaluation, context: ClassificationContext) -> Intervention {
        switch category {
        case .completeForgetting:
            return Intervention(kind: .relearnAndRetest, followUpType: .freeRecall, showExplanation: true,
                                focusPoints: [], comparisonTitle: nil, prerequisiteTitles: [])
        case .partialRecall:
            return Intervention(kind: .focusMissing, followUpType: .cloze, showExplanation: false,
                                focusPoints: evaluation.missingPoints, comparisonTitle: nil, prerequisiteTitles: [])
        case .conceptConfusion:
            return Intervention(kind: .compareConcepts, followUpType: .comparison, showExplanation: true,
                                focusPoints: [], comparisonTitle: context.confusedWithTitle ?? evaluation.confusedWith,
                                prerequisiteTitles: [])
        case .misconception:
            return Intervention(kind: .correctMisconception, followUpType: .explanation, showExplanation: true,
                                focusPoints: evaluation.misconceptions, comparisonTitle: nil, prerequisiteTitles: [])
        case .retrievalFailure:
            return Intervention(kind: .cuedThenBlindRecall, followUpType: .blindRecall, showExplanation: false,
                                focusPoints: [], comparisonTitle: nil, prerequisiteTitles: [])
        case .recognitionWithoutRecall:
            return Intervention(kind: .blindRecall, followUpType: .freeRecall, showExplanation: false,
                                focusPoints: [], comparisonTitle: nil, prerequisiteTitles: [])
        case .guessing:
            return Intervention(kind: .confidenceRecheck, followUpType: .shortAnswer, showExplanation: true,
                                focusPoints: [], comparisonTitle: nil, prerequisiteTitles: [])
        case .applicationFailure:
            return Intervention(kind: .transferPractice, followUpType: .transferNear, showExplanation: true,
                                focusPoints: [], comparisonTitle: nil, prerequisiteTitles: [])
        case .overconfidence:
            return Intervention(kind: .calibrationNotice, followUpType: .question, showExplanation: true,
                                focusPoints: [], comparisonTitle: nil, prerequisiteTitles: [])
        case .missingPrerequisite:
            return Intervention(kind: .reviewPrerequisites, followUpType: nil, showExplanation: true,
                                focusPoints: [], comparisonTitle: nil, prerequisiteTitles: context.weakPrerequisiteTitles)
        }
    }
}
