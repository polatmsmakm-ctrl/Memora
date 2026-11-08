import Foundation
import WidgetKit

/// Builds and publishes the widget snapshot after every save.
enum WidgetSync {
    static let horizonDays: Double = 3
    static let maxDates = 400

    static func makeSnapshot(db: AppDatabase, scheduler: FSRSScheduler, now: Date) -> WidgetSnapshot {
        let horizon = now.addingTimeInterval(horizonDays * 86_400)
        let introduced = db.items.filter { $0.isIntroduced && !$0.isSuspended }
        let dueDates = introduced.map(\.card.due).filter { $0 <= horizon }.sorted().prefix(maxDates)
        let weak = introduced.filter { MemoryStateClassifier.state(of: $0, scheduler: scheduler, now: now) == .weak }.count
        let reviewItems = introduced.filter { $0.card.state == .review }
        let predicted: Double? = reviewItems.isEmpty ? nil
            : reviewItems.map { scheduler.retrievability(of: $0.card, at: now) }.reduce(0, +) / Double(reviewItems.count)
        let reviewedToday = db.reviewLogs.filter { Calendar.current.isDate($0.date, inSameDayAs: now) && $0.countedForScheduling }.count
        return WidgetSnapshot(dueDates: Array(dueDates),
                              weakCount: weak,
                              predictedRetention: predicted,
                              reviewedToday: reviewedToday,
                              secondsPerReview: AnalyticsEngine.averageSecondsPerReview(logs: db.reviewLogs),
                              languageCode: db.settings.language.rawValue,
                              updatedAt: now)
    }

    private static var lastPublished: WidgetSnapshot?

    /// Writes the snapshot and asks WidgetKit to reload only when the content changed,
    /// to respect the widget reload budget.
    static func publish(db: AppDatabase, scheduler: FSRSScheduler, now: Date) {
        let snapshot = makeSnapshot(db: db, scheduler: scheduler, now: now)
        var comparable = snapshot
        comparable.updatedAt = lastPublished?.updatedAt ?? snapshot.updatedAt
        if let last = lastPublished, last == comparable { return }
        if snapshot.save() {
            lastPublished = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
