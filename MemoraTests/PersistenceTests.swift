import XCTest
@testable import Memora

final class PersistenceTests: XCTestCase {
    func testRoundTripEncodeDecode() throws {
        var db = AppDatabase()
        let subject = Subject(name: "Biology")
        db.subjects = [subject]
        var item = LearningItem(subjectID: subject.id, title: "Cell", prompt: "What is a cell?", answer: "The basic unit of life")
        item.mnemonics = [Mnemonic(kind: .acronym, content: "BUL", explanation: "", origin: .local)]
        db.items = [item]
        db.settings.language = .english
        let data = try DatabaseIO.encode(db)
        let decoded = try DatabaseIO.decode(data)
        XCTAssertEqual(decoded.items.first?.id, item.id)
        XCTAssertEqual(decoded.items.first?.mnemonics.first?.content, "BUL")
        XCTAssertEqual(decoded.settings.language, .english)
        XCTAssertEqual(decoded.schemaVersion, AppDatabase.currentSchemaVersion)
    }

    /// A v1 file lacks promptVariants/transferProblems on items and the palaces/pretests arrays.
    func testMigrationFromVersion1() throws {
        var db = AppDatabase()
        let subject = Subject(name: "History")
        db.subjects = [subject]
        db.items = [LearningItem(subjectID: subject.id, title: "Treaty", prompt: "When?", answer: "1648")]
        let encoded = try DatabaseIO.encode(db)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["schemaVersion"] = 1
        json.removeValue(forKey: "palaces")
        json.removeValue(forKey: "pretests")
        var items = try XCTUnwrap(json["items"] as? [[String: Any]])
        items[0].removeValue(forKey: "promptVariants")
        items[0].removeValue(forKey: "transferProblems")
        json["items"] = items
        let v1Data = try JSONSerialization.data(withJSONObject: json)

        let migrated = try DatabaseIO.decode(v1Data)
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.items.count, 1)
        XCTAssertTrue(migrated.items[0].promptVariants.isEmpty)
        XCTAssertTrue(migrated.palaces.isEmpty)
    }

    func testFutureVersionIsRejected() throws {
        let json: [String: Any] = ["schemaVersion": 99]
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try DatabaseIO.decode(data))
    }

    func testSettingsDecodeToleratesMissingKeys() throws {
        let json = #"{"language":"en"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.language, .english)
        XCTAssertEqual(settings.fsrs.desiredRetention, 0.9)
        XCTAssertTrue(settings.reminders.enabled)
    }

    func testMergePrefersNewestItemAndUnionsLogs() {
        let subject = Subject(name: "S")
        var local = AppDatabase()
        local.subjects = [subject]
        var item = LearningItem(subjectID: subject.id, title: "Old", prompt: "p", answer: "a")
        item.updatedAt = Date(timeIntervalSince1970: 100)
        local.items = [item]
        var incoming = local
        var newer = item
        newer.title = "New"
        newer.updatedAt = Date(timeIntervalSince1970: 200)
        incoming.items = [newer]
        let log = ReviewLog(itemID: item.id, subjectID: subject.id, sessionID: UUID(), date: Date(), mode: .remember,
                            exerciseType: .shortAnswer, outcome: .correct, score: 1, rating: .good, confidence: nil, hintsUsed: 0,
                            responseSeconds: 3, errorCategory: nil, evaluationSource: .local, countedForScheduling: true,
                            elapsedDays: 1, retrievabilityBefore: 0.9, stabilityBefore: 1, stabilityAfter: 2, difficultyAfter: 5,
                            scheduledDays: 2, userAnswer: "a")
        incoming.reviewLogs = [log]
        let merged = BackupService.merge(local: local, incoming: incoming)
        XCTAssertEqual(merged.items.count, 1)
        XCTAssertEqual(merged.items[0].title, "New")
        XCTAssertEqual(merged.reviewLogs.count, 1)
    }

    func testBackupRoundTrip() throws {
        var db = AppDatabase()
        db.subjects = [Subject(name: "Physics")]
        let data = try BackupService.makeBackupData(db: db, includeImages: false)
        let backup = try BackupService.decodeBackup(data)
        XCTAssertEqual(backup.database.subjects.first?.name, "Physics")
        XCTAssertThrowsError(try BackupService.decodeBackup(Data(#"{"format":"other"}"#.utf8)))
    }

    func testZipReaderRejectsNonZip() {
        XCTAssertThrowsError(try ZipArchiveReader(data: Data("hello".utf8)))
    }
}
