import XCTest
@testable import Memora

final class SessionBuilderTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func builder(settings: AppSettings = AppSettings()) -> SessionBuilder {
        SessionBuilder(scheduler: FSRSScheduler(parameters: settings.fsrs), settings: settings, now: now)
    }

    private func item(_ subject: UUID, _ title: String, kind: ItemKind = .concept, offset: Double = 0) -> LearningItem {
        LearningItem(subjectID: subject, kind: kind, title: title, prompt: "Q " + title, answer: "Answer about " + title,
                     createdAt: now.addingTimeInterval(offset))
    }

    func testPrerequisitesComeFirst() {
        let s = UUID()
        let advanced = item(s, "Advanced", offset: 0)
        let basic = item(s, "Basic", offset: 10)
        let link = ConceptLink(fromID: basic.id, toID: advanced.id, kind: .prerequisite, origin: .user)
        let ordered = builder().orderedNewItems(pool: [advanced, basic], links: [link], limit: 10)
        XCTAssertEqual(ordered.map(\.title), ["Basic", "Advanced"])
    }

    func testDailyNewLimitIsRespected() {
        var settings = AppSettings()
        settings.dailyNewLimit = 2
        let s = UUID()
        var db = AppDatabase()
        db.items = (0..<5).map { item(s, "I\($0)", offset: Double($0)) }
        var rng = SeededGenerator(seed: 1)
        let items = builder(settings: settings).selectItems(for: SessionRequest(mode: .learn), in: db, excluded: [], rng: &rng)
        XCTAssertEqual(items.count, 2)
    }

    func testInterleavingKeepsUnrelatedSubjectsBlocked() {
        let s1 = UUID(), s2 = UUID()
        let items = [item(s1, "A1", kind: .definition), item(s1, "A2", kind: .process), item(s2, "B1"), item(s1, "A3", kind: .definition), item(s2, "B2")]
        let result = builder().interleave(items, links: [])
        let subjects = result.map(\.subjectID)
        XCTAssertEqual(Array(subjects.prefix(3)), [s1, s1, s1])
        XCTAssertEqual(Array(subjects.suffix(2)), [s2, s2])
        // inside subject 1 the two definitions are separated by the process item
        XCTAssertEqual(result.prefix(3).map(\.title), ["A1", "A2", "A3"])
    }

    func testInterleavingMixesLinkedSubjects() {
        let s1 = UUID(), s2 = UUID()
        let a = item(s1, "A"), a2 = item(s1, "A2"), b = item(s2, "B"), b2 = item(s2, "B2")
        let link = ConceptLink(fromID: a.id, toID: b.id, kind: .related, origin: .user)
        let result = builder().interleave([a, a2, b, b2], links: [link])
        XCTAssertEqual(result.map(\.title), ["A", "B", "A2", "B2"])
    }

    func testSmartReviewPrioritisesLowestRetrievability() {
        let s = UUID()
        let scheduler = FSRSScheduler()
        var weak = item(s, "Weak")
        var strong = item(s, "Strong")
        weak.card = scheduler.review(FSRSCard(due: now), rating: .easy, at: now.addingTimeInterval(-60 * 86_400)).card
        strong.card = scheduler.review(FSRSCard(due: now), rating: .easy, at: now.addingTimeInterval(-17 * 86_400)).card
        var db = AppDatabase()
        db.items = [strong, weak]
        var rng = SeededGenerator(seed: 2)
        let selected = builder().selectItems(for: SessionRequest(mode: .smartReview), in: db, excluded: [], rng: &rng)
        XCTAssertEqual(selected.first?.title, "Weak")
    }

    func testExerciseFactoryFallsBackWhenFormatUnavailable() {
        let s = UUID()
        var rng = SeededGenerator(seed: 3)
        let ex = ExerciseFactory.make(.image, for: item(s, "NoImage"), siblings: [], rng: &rng)
        XCTAssertEqual(ex.type, .shortAnswer)
        let mc = ExerciseFactory.make(.multipleChoice, for: item(s, "Alone"), siblings: [], rng: &rng)
        XCTAssertEqual(mc.type, .shortAnswer)
    }

    func testMultipleChoiceContainsCorrectAnswer() {
        let s = UUID()
        let target = item(s, "T")
        let siblings = [item(s, "X"), item(s, "Y"), item(s, "Z")]
        var rng = SeededGenerator(seed: 4)
        let ex = ExerciseFactory.make(.multipleChoice, for: target, siblings: siblings, rng: &rng)
        XCTAssertEqual(ex.type, .multipleChoice)
        XCTAssertEqual(ex.choices.count, 4)
        XCTAssertEqual(ex.choices[ex.correctChoiceIndex!], target.answer)
    }

    func testPromptNeverContainsAnswerForRecallFormats() {
        let s = UUID()
        var target = item(s, "Mitochondria")
        target.answer = "powerhouse of the cell"
        target.keyPoints = ["powerhouse"]
        var rng = SeededGenerator(seed: 5)
        for type in [ExerciseType.freeRecall, .shortAnswer, .cloze, .keyword, .explanation, .blindRecall] {
            let ex = ExerciseFactory.make(type, for: target, siblings: [], rng: &rng)
            XCTAssertFalse(ex.prompt.contains("powerhouse"), "\(type) leaks the answer")
        }
    }

    func testSeededGeneratorIsDeterministic() {
        var a = SeededGenerator(seed: 42), b = SeededGenerator(seed: 42)
        XCTAssertEqual((0..<5).map { _ in a.next() }, (0..<5).map { _ in b.next() })
    }

    func testStringsTableHasBothLanguages() {
        for (key, entry) in StringsTable.all {
            XCTAssertFalse(entry.ar.isEmpty, "Missing Arabic for \(key)")
            XCTAssertFalse(entry.en.isEmpty, "Missing English for \(key)")
        }
        for mode in StudyMode.allCases {
            XCTAssertNotNil(StringsTable.all["mode.\(mode.rawValue)"])
            XCTAssertNotNil(StringsTable.all["mode.\(mode.rawValue).desc"])
        }
        for category in ErrorCategory.allCases {
            XCTAssertNotNil(StringsTable.all["error.\(category.rawValue).desc"])
        }
        for type in ExerciseType.allCases {
            XCTAssertNotNil(StringsTable.all["exercise.\(type.rawValue)"])
        }
    }
}
