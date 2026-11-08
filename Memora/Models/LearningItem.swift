import Foundation

/// Pointer back to the exact place in the imported material, so the learner can verify.
struct SourceReference: Codable, Hashable {
    var sourceID: UUID
    var sectionHeading: String?
    var pageNumber: Int?
    var quote: String
}

/// Alternative wording of the same retrieval target (contextual variability).
struct PromptVariant: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var prompt: String
    var answer: String
    var origin: ContentOrigin
}

/// Elaborative-interrogation question (why / how / cause / what-if).
struct ElaborationQuestion: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var kind: ElaborationKind
    var question: String
    var answer: String
    var origin: ContentOrigin
}

/// Unfamiliar problem that requires applying the concept (near or far transfer).
struct TransferProblem: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var level: TransferLevel
    var problem: String
    var solution: String
    var origin: ContentOrigin
}

struct Mnemonic: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var kind: MnemonicKind
    var content: String
    var explanation: String
    var origin: ContentOrigin
    var createdAt: Date = Date()
}

struct ConfidenceSample: Codable, Hashable {
    var date: Date
    var confidence: ConfidenceLevel
    var wasCorrect: Bool
}

struct SuccessTally: Codable, Hashable {
    var attempts: Int = 0
    var successes: Int = 0
    var rate: Double? { attempts == 0 ? nil : Double(successes) / Double(attempts) }
}

/// Learning-state data that lives *beside* FSRS. Nothing in here feeds the FSRS
/// formulas; it only drives memory-state classification, interventions and analytics.
struct MemoryProfile: Codable, Hashable {
    var successCount: Int = 0
    var failureCount: Int = 0
    var partialCount: Int = 0
    var confidenceHistory: [ConfidenceSample] = []
    var errorCounts: [String: Int] = [:]
    var lastErrorCategory: ErrorCategory? = nil
    /// Start-of-day dates on which the item was retrieved correctly (successive relearning).
    var successfulSessionDays: [Date] = []
    var sessionIDs: [UUID] = []
    /// Correct recalls after a delay of 21+ days since the previous review.
    var delayedRecallSuccesses: Int = 0
    var masteryRevokedAt: Date? = nil
    var lastOutcomes: [Outcome] = []
    var lastExerciseType: ExerciseType? = nil
    var lastVariantIndex: Int? = nil
    var bucketStats: [String: SuccessTally] = [:]

    var distinctSuccessfulDays: Int { successfulSessionDays.count }
    var totalAttempts: Int { successCount + failureCount + partialCount }

    func errorCount(_ category: ErrorCategory) -> Int { errorCounts[category.rawValue] ?? 0 }
    func tally(_ bucket: KnowledgeBucket) -> SuccessTally { bucketStats[bucket.rawValue] ?? SuccessTally() }

    func hasSuccess(on day: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: day)
        return successfulSessionDays.contains { calendar.isDate($0, inSameDayAs: start) }
    }
}

/// One meaningful learning unit (not a throw-away flashcard) with its own memory profile.
struct LearningItem: Codable, Identifiable, Hashable {
    var id: UUID
    var subjectID: UUID
    var kind: ItemKind
    var title: String
    var prompt: String
    var answer: String
    var keyPoints: [String]
    var explanation: String
    var examples: [String]
    var analogies: [String]
    var hints: [String]
    var elaborations: [ElaborationQuestion]
    var transferProblems: [TransferProblem]
    var promptVariants: [PromptVariant]
    var mnemonics: [Mnemonic]
    var imageFileName: String?
    var sourceReference: SourceReference?
    var tags: [String]
    var origin: ContentOrigin
    var priorKnowledge: PriorKnowledge
    var createdAt: Date
    var updatedAt: Date
    var introducedAt: Date?
    var pretestedAt: Date?
    var isSuspended: Bool
    var card: FSRSCard
    var profile: MemoryProfile

    init(id: UUID = UUID(),
         subjectID: UUID,
         kind: ItemKind = .concept,
         title: String,
         prompt: String,
         answer: String,
         keyPoints: [String] = [],
         explanation: String = "",
         examples: [String] = [],
         analogies: [String] = [],
         hints: [String] = [],
         elaborations: [ElaborationQuestion] = [],
         transferProblems: [TransferProblem] = [],
         promptVariants: [PromptVariant] = [],
         mnemonics: [Mnemonic] = [],
         imageFileName: String? = nil,
         sourceReference: SourceReference? = nil,
         tags: [String] = [],
         origin: ContentOrigin = .user,
         priorKnowledge: PriorKnowledge = .unknown,
         createdAt: Date = Date()) {
        self.id = id
        self.subjectID = subjectID
        self.kind = kind
        self.title = title
        self.prompt = prompt
        self.answer = answer
        self.keyPoints = keyPoints
        self.explanation = explanation
        self.examples = examples
        self.analogies = analogies
        self.hints = hints
        self.elaborations = elaborations
        self.transferProblems = transferProblems
        self.promptVariants = promptVariants
        self.mnemonics = mnemonics
        self.imageFileName = imageFileName
        self.sourceReference = sourceReference
        self.tags = tags
        self.origin = origin
        self.priorKnowledge = priorKnowledge
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.introducedAt = nil
        self.pretestedAt = nil
        self.isSuspended = false
        self.card = FSRSCard(due: createdAt)
        self.profile = MemoryProfile()
    }

    /// Key points used for grading; derived from the answer when none were authored.
    var gradingPoints: [String] {
        let cleaned = keyPoints.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return cleaned.isEmpty ? TextNormalizer.keyTerms(from: answer, limit: 5) : cleaned
    }

    var isIntroduced: Bool { card.state != .new }

    /// Resets all scheduling and profile data while keeping content.
    mutating func resetProgress(now: Date = Date()) {
        card = FSRSCard(due: now)
        profile = MemoryProfile()
        introducedAt = nil
        pretestedAt = nil
        updatedAt = now
    }
}
