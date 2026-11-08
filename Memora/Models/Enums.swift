import Foundation

// MARK: - FSRS primitives

/// FSRS review grade. Values match the FSRS reference implementation (1...4).
enum Rating: Int, Codable, CaseIterable, Identifiable {
    case again = 1, hard = 2, good = 3, easy = 4
    var id: Int { rawValue }
    var title: String { L("rating.\(String(describing: self))") }
}

/// Raw FSRS scheduling state. Kept strictly separate from `MemoryState`,
/// which is a richer, learner-facing classification computed on top of it.
enum CardState: Int, Codable {
    case new = 0, learning = 1, review = 2, relearning = 3
}

// MARK: - Learner-facing memory model

enum MemoryState: String, Codable, CaseIterable, Identifiable {
    case unseen, new, learning, developing, longTerm, weak, relearning
    var id: String { rawValue }
    var title: String { L("state.\(rawValue)") }
    var detail: String { L("state.\(rawValue).desc") }
    var systemImage: String {
        switch self {
        case .unseen: return "circle.dashed"
        case .new: return "sparkle"
        case .learning: return "arrow.triangle.2.circlepath"
        case .developing: return "chart.line.uptrend.xyaxis"
        case .longTerm: return "checkmark.seal"
        case .weak: return "exclamationmark.triangle"
        case .relearning: return "arrow.uturn.backward.circle"
        }
    }
}

enum ConfidenceLevel: Int, Codable, CaseIterable, Identifiable {
    case guess = 0, unsure = 1, fairly = 2, certain = 3
    var id: Int { rawValue }
    /// Subjective probability of being correct used for calibration analysis.
    var probability: Double { [0.25, 0.5, 0.75, 0.95][rawValue] }
    var isHigh: Bool { rawValue >= 2 }
    var title: String { L("confidence.\(String(describing: self))") }
}

enum Outcome: String, Codable, CaseIterable {
    case correct, partial, incorrect, noAnswer
    var isSuccess: Bool { self == .correct }
    var isFailure: Bool { self == .incorrect || self == .noAnswer }
    var title: String { L("outcome.\(rawValue)") }
    var score: Double {
        switch self {
        case .correct: return 1
        case .partial: return 0.5
        case .incorrect, .noAnswer: return 0
        }
    }
}

enum EvaluationSource: String, Codable {
    case local, ai, selfGraded
}

enum ErrorCategory: String, Codable, CaseIterable, Identifiable {
    case completeForgetting
    case partialRecall
    case conceptConfusion
    case misconception
    case retrievalFailure
    case recognitionWithoutRecall
    case guessing
    case applicationFailure
    case overconfidence
    case missingPrerequisite

    var id: String { rawValue }
    var title: String { L("error.\(rawValue)") }
    var detail: String { L("error.\(rawValue).desc") }
    var systemImage: String {
        switch self {
        case .completeForgetting: return "cloud.fog"
        case .partialRecall: return "circle.lefthalf.filled"
        case .conceptConfusion: return "arrow.left.arrow.right"
        case .misconception: return "exclamationmark.bubble"
        case .retrievalFailure: return "key"
        case .recognitionWithoutRecall: return "eye"
        case .guessing: return "dice"
        case .applicationFailure: return "wrench.and.screwdriver"
        case .overconfidence: return "gauge.with.dots.needle.100percent"
        case .missingPrerequisite: return "square.stack.3d.down.right"
        }
    }
}

// MARK: - Exercises and modes

enum KnowledgeBucket: String, Codable, CaseIterable, Identifiable {
    case direct, conceptual, near, far
    var id: String { rawValue }
    var title: String { L("bucket.\(rawValue)") }
}

enum ExerciseType: String, Codable, CaseIterable, Identifiable {
    case freeRecall, shortAnswer, cloze, multipleChoice, reverse, keyword
    case explanation, image, question, elaboration, selfExplanation
    case transferNear, transferFar, comparison, blindRecall, restudy, palace

    var id: String { rawValue }
    var title: String { L("exercise.\(rawValue)") }
    var isTransfer: Bool { self == .transferNear || self == .transferFar }
    /// Recall (production) as opposed to recognition or restudy.
    var isRecallBased: Bool { self != .multipleChoice && self != .restudy }
    var usesTextInput: Bool { self != .multipleChoice && self != .restudy }
    /// Open-ended formats where a lexical check is weak and AI grading adds value.
    var benefitsFromAI: Bool {
        switch self {
        case .freeRecall, .explanation, .selfExplanation, .elaboration, .transferNear,
             .transferFar, .comparison, .question, .blindRecall, .palace:
            return true
        default:
            return false
        }
    }
    var bucket: KnowledgeBucket {
        switch self {
        case .transferNear: return .near
        case .transferFar: return .far
        case .explanation, .elaboration, .selfExplanation, .comparison: return .conceptual
        default: return .direct
        }
    }
}

enum StudyMode: String, Codable, CaseIterable, Identifiable {
    case learn, remember, smartReview, deepUnderstanding, exam, memoryRescue, longTerm
    case quickDaily, blindRecall, pretest, transfer, successiveRelearning, experiment, palaceWalk

    var id: String { rawValue }
    var title: String { L("mode.\(rawValue)") }
    var detail: String { L("mode.\(rawValue).desc") }
    var systemImage: String {
        switch self {
        case .learn: return "book"
        case .remember: return "brain.head.profile"
        case .smartReview: return "sparkles"
        case .deepUnderstanding: return "magnifyingglass"
        case .exam: return "doc.text.magnifyingglass"
        case .memoryRescue: return "lifepreserver"
        case .longTerm: return "hourglass"
        case .quickDaily: return "bolt"
        case .blindRecall: return "eye.slash"
        case .pretest: return "questionmark.circle"
        case .transfer: return "arrow.triangle.branch"
        case .successiveRelearning: return "repeat"
        case .experiment: return "flask"
        case .palaceWalk: return "building.columns"
        }
    }
}

// MARK: - Content

enum ItemKind: String, Codable, CaseIterable, Identifiable {
    case fact, definition, concept, process, relationship, vocabulary
    var id: String { rawValue }
    var title: String { L("kind.\(rawValue)") }
}

enum LinkKind: String, Codable, CaseIterable, Identifiable {
    /// `from` is a prerequisite of `to`.
    case prerequisite
    case related, partOf, contrastsWith, causes, example
    var id: String { rawValue }
    var title: String { L("link.\(rawValue)") }
}

enum MnemonicKind: String, Codable, CaseIterable, Identifiable {
    case memoryPalace, acronym, acrostic, chunking, keyword, imagery, narrative, association
    var id: String { rawValue }
    var title: String { L("mnemonic.\(rawValue)") }
}

enum TransferLevel: String, Codable, CaseIterable, Identifiable {
    case near, far
    var id: String { rawValue }
    var title: String { L("transfer.\(rawValue)") }
}

enum ElaborationKind: String, Codable, CaseIterable, Identifiable {
    case why, how, cause, whatIf
    var id: String { rawValue }
    var title: String { L("elab.\(rawValue)") }
}

enum PriorKnowledge: String, Codable, CaseIterable, Identifiable {
    case unknown, known, partial, new
    var id: String { rawValue }
    var title: String { L("prior.\(rawValue)") }
}

enum SourceKind: String, Codable, CaseIterable, Identifiable {
    case text, note, pdf, docx, image, audio, manual, ai
    var id: String { rawValue }
    var title: String { L("source.\(rawValue)") }
    var systemImage: String {
        switch self {
        case .text: return "text.alignleft"
        case .note: return "note.text"
        case .pdf: return "doc.richtext"
        case .docx: return "doc.text"
        case .image: return "photo"
        case .audio: return "waveform"
        case .manual: return "square.and.pencil"
        case .ai: return "sparkles"
        }
    }
}

/// Where a piece of content came from. Imported text is never silently rewritten:
/// AI material is stored separately and flagged with `.ai`.
enum ContentOrigin: String, Codable, CaseIterable {
    case source, local, user, ai
    var title: String { L("origin.\(rawValue)") }
}
