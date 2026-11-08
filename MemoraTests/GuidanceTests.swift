import XCTest
@testable import Memora

final class GuidanceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "memora.tests.guidance"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testVersion2DatabaseMigratesWithFreshGuidance() throws {
        var db = AppDatabase()
        db.subjects = [Subject(name: "S")]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: DatabaseIO.encode(db)) as? [String: Any])
        json["schemaVersion"] = 2
        json.removeValue(forKey: "guidance")
        let migrated = try DatabaseIO.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.schemaVersion, 3)
        XCTAssertFalse(migrated.guidance.tourCompleted)
        XCTAssertTrue(migrated.guidance.seenTips.isEmpty)
        XCTAssertEqual(migrated.subjects.count, 1)
    }

    func testCompletedTourSurvivesSaveAndReload() throws {
        var db = AppDatabase()
        db.guidance.tourCompleted = true
        db.guidance.seenTips = ["knowledgeGraph"]
        let reloaded = try DatabaseIO.decode(DatabaseIO.encode(db))
        XCTAssertTrue(reloaded.guidance.tourCompleted)
        XCTAssertEqual(reloaded.guidance.seenTips, ["knowledgeGraph"])
    }

    func testGuidanceDecodesWithMissingKeys() throws {
        let state = try JSONDecoder().decode(GuidanceState.self, from: Data(#"{"tourCompleted":true}"#.utf8))
        XCTAssertTrue(state.tourCompleted)
        XCTAssertTrue(state.seenTips.isEmpty)
    }

    func testMergeNeverLosesCompletionOrTips() {
        var a = GuidanceState()
        a.seenTips = ["experiments"]
        var b = GuidanceState()
        b.tourCompleted = true
        b.seenTips = ["experiments", "blindRecall"]
        let merged = GuidanceState.merged(a, b)
        XCTAssertTrue(merged.tourCompleted)
        XCTAssertEqual(merged.seenTips, ["experiments", "blindRecall"])
    }

    func testMirrorRestoresCompletionAfterLostDatabase() {
        let mirror = GuidanceMirror(defaults: defaults)
        var state = GuidanceState()
        state.tourCompleted = true
        state.seenTips = ["coachModes"]
        mirror.save(state)
        // Simulates a quarantined/unreadable database that starts fresh.
        let recovered = mirror.reconcile(GuidanceState())
        XCTAssertTrue(recovered.tourCompleted)
        XCTAssertEqual(recovered.seenTips, ["coachModes"])
    }

    func testTipsAreTrackedIndependently() {
        var state = GuidanceState()
        state.seenTips.append(FeatureTip.knowledgeGraph.rawValue)
        XCTAssertTrue(state.hasSeenTip(FeatureTip.knowledgeGraph.rawValue))
        for tip in FeatureTip.allCases where tip != .knowledgeGraph {
            XCTAssertFalse(state.hasSeenTip(tip.rawValue))
        }
    }

    func testBackupMergeKeepsLocalCompletion() {
        var local = AppDatabase()
        local.guidance.tourCompleted = true
        let incoming = AppDatabase()
        XCTAssertTrue(BackupService.merge(local: local, incoming: incoming).guidance.tourCompleted)
    }

    func testTourHasUniqueStepsAndAnchors() {
        let steps = GuideTour.steps
        XCTAssertEqual(steps.count, 8)
        XCTAssertEqual(Set(steps.map(\.id)).count, steps.count)
        XCTAssertEqual(Set(steps.map(\.anchor)).count, steps.count)
    }

    func testAllGuidanceStringsExistInBothLanguages() {
        for step in GuideTour.steps {
            for suffix in ["title", "body"] {
                let entry = StringsTable.all["tour.\(step.id).\(suffix)"]
                XCTAssertNotNil(entry, "missing tour.\(step.id).\(suffix)")
            }
        }
        for tip in FeatureTip.allCases {
            XCTAssertNotNil(StringsTable.all["tip.\(tip.rawValue).title"])
            XCTAssertNotNil(StringsTable.all["tip.\(tip.rawValue).body"])
        }
        XCTAssertNotNil(StringsTable.all["help.replay"])
    }
}
