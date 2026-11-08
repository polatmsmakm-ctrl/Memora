import Foundation

struct Subject: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var details: String = ""
    var symbol: String = "book.closed"
    var createdAt: Date = Date()
    var isArchived: Bool = false
}

struct SourceSection: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var heading: String?
    var level: Int = 0
    var text: String
    var pageNumber: Int?
}

/// Imported material kept verbatim so every learning unit can be verified against it.
struct SourceDocument: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var subjectID: UUID
    var title: String
    var kind: SourceKind
    var importedAt: Date = Date()
    var text: String
    var sections: [SourceSection]
    var originalFileName: String?
}

/// Directed relation between two learning items (knowledge graph edge).
struct ConceptLink: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var fromID: UUID
    var toID: UUID
    var kind: LinkKind
    var origin: ContentOrigin
    var createdAt: Date = Date()
}

/// One retrieval attempt. Contains both what was *measured* (outcome, confidence)
/// and what the algorithm *predicted* (retrievabilityBefore) so the two never get mixed up.
struct ReviewLog: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var itemID: UUID
    var subjectID: UUID
    var sessionID: UUID
    var date: Date
    var mode: StudyMode
    var exerciseType: ExerciseType
    var outcome: Outcome
    var score: Double
    var rating: Rating?
    var confidence: ConfidenceLevel?
    var hintsUsed: Int
    var responseSeconds: Double
    var errorCategory: ErrorCategory?
    var evaluationSource: EvaluationSource
    var countedForScheduling: Bool
    var elapsedDays: Double
    var retrievabilityBefore: Double
    var stabilityBefore: Double
    var stabilityAfter: Double
    var difficultyAfter: Double
    var scheduledDays: Double
    var userAnswer: String
}

struct StudySessionRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var mode: StudyMode
    var subjectID: UUID?
    var startedAt: Date
    var endedAt: Date
    var attempts: Int
    var correct: Int
    var partial: Int
    var incorrect: Int
    var durationSeconds: Double { endedAt.timeIntervalSince(startedAt) }
}

enum PretestPhase: String, Codable {
    case pre, post
}

/// Pretest attempts are recorded separately and never touch FSRS.
struct PretestRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var itemID: UUID
    var date: Date
    var phase: PretestPhase
    var score: Double
    var outcome: Outcome
}

struct Locus: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var itemID: UUID?
}

/// Method of loci: an ordered route of familiar places, each holding one item.
struct MemoryPalace: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var details: String = ""
    var loci: [Locus] = []
    var createdAt: Date = Date()
}
