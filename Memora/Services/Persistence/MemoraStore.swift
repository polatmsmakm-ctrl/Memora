import Foundation
import SwiftUI

/// Single source of truth for the app. All mutations go through this type, which
/// persists the database (debounced, atomic writes) and refreshes the widget snapshot.
@MainActor
final class MemoraStore: ObservableObject {
    @Published private(set) var db: AppDatabase
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            Localizer.language = settings.language
            db.settings = settings
            scheduleSave()
        }
    }
    @Published var lastError: String?

    let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL = FileLocations.databaseURL) {
        self.fileURL = fileURL
        var loaded = AppDatabase()
        var loadError: String?
        do {
            if let existing = try DatabaseIO.load(from: fileURL) { loaded = existing }
        } catch {
            DatabaseIO.quarantine(fileURL)
            loadError = error.localizedDescription
        }
        loaded.guidance = GuidanceMirror.standard.reconcile(loaded.guidance)
        GuidanceMirror.standard.save(loaded.guidance)
        self.db = loaded
        self.settings = loaded.settings
        self.lastError = loadError
        Localizer.language = loaded.settings.language
    }

    // MARK: Guidance (onboarding)

    var guidance: GuidanceState { db.guidance }

    /// Records that the tour was finished or skipped. Saved immediately so it survives
    /// a crash or force-quit right after the tour.
    func markTourFinished(skipped: Bool) {
        db.guidance.tourCompleted = true
        db.guidance.tourSkipped = db.guidance.tourSkipped || skipped
        if db.guidance.tourCompletedAt == nil { db.guidance.tourCompletedAt = Date() }
        GuidanceMirror.standard.save(db.guidance)
        saveNow()
    }

    func markTipSeen(_ id: String) {
        guard !db.guidance.seenTips.contains(id) else { return }
        db.guidance.seenTips.append(id)
        GuidanceMirror.standard.save(db.guidance)
        scheduleSave()
    }

    /// Lets every one-time feature tip appear again (Help → Show tips again).
    func resetFeatureTips() {
        db.guidance.seenTips = []
        GuidanceMirror.standard.save(db.guidance)
        saveNow()
    }

    var scheduler: FSRSScheduler { FSRSScheduler(parameters: settings.fsrs) }

    // MARK: Queries

    var itemsByID: [UUID: LearningItem] {
        Dictionary(db.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func item(_ id: UUID) -> LearningItem? { db.items.first { $0.id == id } }
    func subject(_ id: UUID?) -> Subject? { db.subjects.first { $0.id == id } }
    func source(_ id: UUID?) -> SourceDocument? { db.sources.first { $0.id == id } }

    func items(in subjectID: UUID?) -> [LearningItem] {
        guard let subjectID else { return db.items }
        return db.items.filter { $0.subjectID == subjectID }
    }

    func memoryState(of item: LearningItem, now: Date = Date()) -> MemoryState {
        MemoryStateClassifier.state(of: item, scheduler: scheduler, now: now)
    }

    func retrievability(of item: LearningItem, now: Date = Date()) -> Double {
        scheduler.retrievability(of: item.card, at: now)
    }

    func dueItems(now: Date = Date(), subjectID: UUID? = nil) -> [LearningItem] {
        items(in: subjectID).filter { !$0.isSuspended && scheduler.isDue($0.card, at: now) }
    }

    func newItems(subjectID: UUID?) -> [LearningItem] {
        items(in: subjectID).filter { !$0.isSuspended && $0.card.state == .new }
    }

    func logs(for itemID: UUID) -> [ReviewLog] {
        db.reviewLogs.filter { $0.itemID == itemID }.sorted { $0.date > $1.date }
    }

    func links(for itemID: UUID) -> [ConceptLink] {
        db.links.filter { $0.fromID == itemID || $0.toID == itemID }
    }

    func siblings(of item: LearningItem) -> [LearningItem] {
        db.items.filter { $0.subjectID == item.subjectID && $0.id != item.id }
    }

    func weakPrerequisites(of item: LearningItem, now: Date = Date()) -> [LearningItem] {
        PrerequisiteAnalyzer.weakPrerequisites(of: item, itemsByID: itemsByID, links: db.links, scheduler: scheduler, now: now)
    }

    func classificationContext(for item: LearningItem, answer: String, exerciseType: ExerciseType, now: Date = Date()) -> ClassificationContext {
        let since = now.addingTimeInterval(-14 * 86_400)
        let recognized = db.reviewLogs.contains {
            $0.itemID == item.id && $0.exerciseType == .multipleChoice && $0.outcome == .correct && $0.date >= since
        }
        let candidates = siblings(of: item).filter(\.isIntroduced).map { (title: $0.title, answer: $0.answer) }
        let confused = exerciseType.isRecallBased
            ? AnswerEvaluator.detectConfusion(answer: answer, ownAnswer: item.answer, candidates: candidates)
            : nil
        return ClassificationContext(recognizedRecentlyByMultipleChoice: recognized,
                                     confusedWithTitle: confused,
                                     weakPrerequisiteTitles: weakPrerequisites(of: item, now: now).map(\.title))
    }

    /// Items excluded from normal sessions because they belong to a running experiment.
    var experimentLockedItemIDs: Set<UUID> {
        Set(db.experiments.filter { !$0.isCompleted }.flatMap(\.allItemIDs))
    }

    // MARK: Subjects

    func addSubject(_ subject: Subject) {
        mutate { $0.subjects.append(subject) }
    }

    func updateSubject(_ subject: Subject) {
        mutate { db in
            if let i = db.subjects.firstIndex(where: { $0.id == subject.id }) { db.subjects[i] = subject }
        }
    }

    func deleteSubject(_ id: UUID) {
        let itemIDs = Set(db.items.filter { $0.subjectID == id }.map(\.id))
        for item in db.items where itemIDs.contains(item.id) {
            if let name = item.imageFileName { ImageStore.delete(name) }
        }
        mutate { db in
            db.subjects.removeAll { $0.id == id }
            db.items.removeAll { itemIDs.contains($0.id) }
            db.sources.removeAll { $0.subjectID == id }
            db.reviewLogs.removeAll { itemIDs.contains($0.itemID) }
            db.links.removeAll { itemIDs.contains($0.fromID) || itemIDs.contains($0.toID) }
            db.pretests.removeAll { itemIDs.contains($0.itemID) }
            for p in db.palaces.indices {
                for l in db.palaces[p].loci.indices {
                    guard let locusItem = db.palaces[p].loci[l].itemID, itemIDs.contains(locusItem) else { continue }
                    db.palaces[p].loci[l].itemID = nil
                }
            }
            db.experiments.removeAll { !Set($0.allItemIDs).isDisjoint(with: itemIDs) }
        }
    }

    // MARK: Items

    func upsertItem(_ item: LearningItem) {
        var copy = item
        copy.updatedAt = Date()
        mutate { db in
            if let i = db.items.firstIndex(where: { $0.id == copy.id }) { db.items[i] = copy } else { db.items.append(copy) }
        }
    }

    func addItems(_ items: [LearningItem]) {
        guard !items.isEmpty else { return }
        mutate { $0.items.append(contentsOf: items) }
    }

    func deleteItem(_ id: UUID) {
        if let name = item(id)?.imageFileName { ImageStore.delete(name) }
        mutate { db in
            db.items.removeAll { $0.id == id }
            db.reviewLogs.removeAll { $0.itemID == id }
            db.links.removeAll { $0.fromID == id || $0.toID == id }
            db.pretests.removeAll { $0.itemID == id }
            for p in db.palaces.indices {
                for l in db.palaces[p].loci.indices where db.palaces[p].loci[l].itemID == id {
                    db.palaces[p].loci[l].itemID = nil
                }
            }
            for e in db.experiments.indices {
                db.experiments[e].itemIDsA.removeAll { $0 == id }
                db.experiments[e].itemIDsB.removeAll { $0 == id }
            }
        }
    }

    func setPriorKnowledge(_ value: PriorKnowledge, for id: UUID) {
        mutate { db in
            if let i = db.items.firstIndex(where: { $0.id == id }) { db.items[i].priorKnowledge = value }
        }
    }

    func markIntroduced(_ id: UUID) {
        mutate { db in
            if let i = db.items.firstIndex(where: { $0.id == id }), db.items[i].introducedAt == nil {
                db.items[i].introducedAt = Date()
            }
        }
    }

    // MARK: Sources & links

    func addSource(_ source: SourceDocument) {
        mutate { $0.sources.append(source) }
    }

    func deleteSource(_ id: UUID) {
        mutate { db in
            db.sources.removeAll { $0.id == id }
            for i in db.items.indices where db.items[i].sourceReference?.sourceID == id {
                db.items[i].sourceReference = nil
            }
        }
    }

    @discardableResult
    func addLink(from: UUID, to: UUID, kind: LinkKind, origin: ContentOrigin = .user) -> Bool {
        guard from != to,
              !db.links.contains(where: { $0.fromID == from && $0.toID == to && $0.kind == kind }) else { return false }
        if kind == .prerequisite && createsPrerequisiteCycle(from: from, to: to) { return false }
        mutate { $0.links.append(ConceptLink(fromID: from, toID: to, kind: kind, origin: origin)) }
        return true
    }

    func addLinks(_ links: [ConceptLink]) {
        var accepted: [ConceptLink] = []
        for link in links where link.fromID != link.toID
            && !db.links.contains(where: { $0.fromID == link.fromID && $0.toID == link.toID && $0.kind == link.kind })
            && !accepted.contains(where: { $0.fromID == link.fromID && $0.toID == link.toID && $0.kind == link.kind }) {
            accepted.append(link)
        }
        guard !accepted.isEmpty else { return }
        mutate { $0.links.append(contentsOf: accepted) }
    }

    func removeLink(_ id: UUID) {
        mutate { $0.links.removeAll { $0.id == id } }
    }

    /// Prevents A→B when B already (transitively) is a prerequisite of A.
    func createsPrerequisiteCycle(from: UUID, to: UUID) -> Bool {
        var stack = [from]
        var visited = Set<UUID>()
        while let current = stack.popLast() {
            if current == to { return true }
            guard visited.insert(current).inserted else { continue }
            stack.append(contentsOf: PrerequisiteAnalyzer.prerequisiteIDs(of: current, links: db.links))
        }
        return false
    }

    // MARK: Attempts & sessions

    func apply(_ result: AttemptResult) {
        mutate { db in
            if let i = db.items.firstIndex(where: { $0.id == result.item.id }) { db.items[i] = result.item }
            db.reviewLogs.append(result.log)
        }
    }

    func recordSession(_ record: StudySessionRecord) {
        guard record.attempts > 0 else { return }
        mutate { $0.sessions.append(record) }
    }

    func addPretest(_ record: PretestRecord) {
        mutate { $0.pretests.append(record) }
    }

    // MARK: Experiments & palaces

    func upsertExperiment(_ experiment: Experiment) {
        mutate { db in
            if let i = db.experiments.firstIndex(where: { $0.id == experiment.id }) { db.experiments[i] = experiment } else { db.experiments.append(experiment) }
        }
    }

    func deleteExperiment(_ id: UUID) { mutate { $0.experiments.removeAll { $0.id == id } } }

    func recordExperimentPractice(_ id: UUID, condition: ExperimentCondition) {
        mutate { db in
            if let i = db.experiments.firstIndex(where: { $0.id == id }) {
                db.experiments[i].practices.append(ExperimentPractice(date: Date(), condition: condition))
            }
        }
    }

    func recordExperimentResults(_ id: UUID, results: [ExperimentTestResult]) {
        guard !results.isEmpty else { return }
        mutate { db in
            if let i = db.experiments.firstIndex(where: { $0.id == id }) { db.experiments[i].results.append(contentsOf: results) }
        }
    }

    func upsertPalace(_ palace: MemoryPalace) {
        mutate { db in
            if let i = db.palaces.firstIndex(where: { $0.id == palace.id }) { db.palaces[i] = palace } else { db.palaces.append(palace) }
        }
    }

    func deletePalace(_ id: UUID) { mutate { $0.palaces.removeAll { $0.id == id } } }

    // MARK: Backup

    func replaceDatabase(with newDB: AppDatabase) {
        var copy = newDB
        copy.settings = settings
        copy.guidance = GuidanceState.merged(db.guidance, newDB.guidance)
        db = copy
        db.lastModified = Date()
        saveNow()
    }

    func merge(with incoming: AppDatabase) {
        db = BackupService.merge(local: db, incoming: incoming)
        db.settings = settings
        db.lastModified = Date()
        saveNow()
    }

    func eraseAll() {
        for item in db.items { if let name = item.imageFileName { ImageStore.delete(name) } }
        var fresh = AppDatabase()
        fresh.settings = settings
        fresh.guidance = db.guidance
        db = fresh
        saveNow()
    }

    // MARK: Persistence

    private func mutate(_ body: (inout AppDatabase) -> Void) {
        body(&db)
        db.lastModified = Date()
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        var snapshot = db
        snapshot.settings = settings
        do {
            let data = try DatabaseIO.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            lastError = error.localizedDescription
        }
        WidgetSync.publish(db: snapshot, scheduler: scheduler, now: Date())
    }
}
