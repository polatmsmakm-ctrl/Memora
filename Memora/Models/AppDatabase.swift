import Foundation

/// The complete on-device database. Persisted as one versioned JSON document;
/// see `DatabaseMigrator` for schema upgrades.
struct AppDatabase: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int = AppDatabase.currentSchemaVersion
    var subjects: [Subject] = []
    var items: [LearningItem] = []
    var sources: [SourceDocument] = []
    var reviewLogs: [ReviewLog] = []
    var links: [ConceptLink] = []
    var sessions: [StudySessionRecord] = []
    var experiments: [Experiment] = []
    var palaces: [MemoryPalace] = []
    var pretests: [PretestRecord] = []
    var settings: AppSettings = AppSettings()
    var lastModified: Date = Date()
}
