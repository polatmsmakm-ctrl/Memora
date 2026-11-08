import Foundation

struct PrerequisiteDiagnosis: Identifiable {
    var id: UUID { item.id }
    var item: LearningItem
    var weakPrerequisites: [LearningItem]
    var recentFailures: Int
}

/// Investigates whether repeated failure on an advanced item is explained by weak foundations.
enum PrerequisiteAnalyzer {
    static let failureWindowDays: Double = 14

    static func prerequisiteIDs(of itemID: UUID, links: [ConceptLink]) -> [UUID] {
        links.filter { $0.kind == .prerequisite && $0.toID == itemID }.map(\.fromID)
    }

    static func dependentIDs(of itemID: UUID, links: [ConceptLink]) -> [UUID] {
        links.filter { $0.kind == .prerequisite && $0.fromID == itemID }.map(\.toID)
    }

    static func isWeakFoundation(_ item: LearningItem, scheduler: FSRSScheduler, now: Date) -> Bool {
        let state = MemoryStateClassifier.state(of: item, scheduler: scheduler, now: now)
        switch state {
        case .unseen, .new, .weak, .relearning:
            return true
        case .learning:
            return item.profile.failureCount > 0
        case .developing, .longTerm:
            return item.profile.failureCount > item.profile.successCount
        }
    }

    static func weakPrerequisites(of item: LearningItem, itemsByID: [UUID: LearningItem], links: [ConceptLink],
                                  scheduler: FSRSScheduler, now: Date) -> [LearningItem] {
        prerequisiteIDs(of: item.id, links: links)
            .compactMap { itemsByID[$0] }
            .filter { isWeakFoundation($0, scheduler: scheduler, now: now) }
    }

    /// Items failed at least twice recently whose prerequisites are weak.
    static func diagnoses(items: [LearningItem], logs: [ReviewLog], links: [ConceptLink],
                          scheduler: FSRSScheduler, now: Date) -> [PrerequisiteDiagnosis] {
        let since = now.addingTimeInterval(-failureWindowDays * 86_400)
        var failures: [UUID: Int] = [:]
        for log in logs where log.date >= since && log.countedForScheduling && log.outcome.isFailure {
            failures[log.itemID, default: 0] += 1
        }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return failures.filter { $0.value >= 2 }.compactMap { id, count in
            guard let item = byID[id] else { return nil }
            let weak = weakPrerequisites(of: item, itemsByID: byID, links: links, scheduler: scheduler, now: now)
            return weak.isEmpty ? nil : PrerequisiteDiagnosis(item: item, weakPrerequisites: weak, recentFailures: count)
        }.sorted { $0.recentFailures > $1.recentFailures }
    }
}
