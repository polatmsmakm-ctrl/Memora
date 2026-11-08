import Foundation

struct DayCount: Identifiable, Hashable {
    var id: Date { day }
    var day: Date
    var count: Int
}

struct DayActivity: Identifiable, Hashable {
    var id: Date { day }
    var day: Date
    var reviews: Int
    var minutes: Double
}

/// Weekly comparison of what FSRS predicted with what was measured.
struct TrendPoint: Identifiable, Hashable {
    var id: Date { weekStart }
    var weekStart: Date
    var measuredRecall: Double
    var predictedRecall: Double
    var reviews: Int
}

struct SubjectStat: Identifiable, Hashable {
    var id: UUID
    var name: String
    var items: Int
    var measuredRecall: Double?
    var predictedRetention: Double?
    var attempts: Int
}

struct MasteryPoint: Identifiable, Hashable {
    var id: Date { weekStart }
    var weekStart: Date
    var cumulative: Int
}

struct AnalyticsSnapshot {
    var totalItems = 0
    var learnedItems = 0
    var successfulRetrievals = 0
    var failedRetrievals = 0
    var partialRetrievals = 0
    var measuredRecall30: Double?
    var predictedRetentionNow: Double?
    var overdue = 0
    var dueToday = 0
    var upcoming: [DayCount] = []
    var stateCounts: [MemoryState: Int] = [:]
    var subjects: [SubjectStat] = []
    var trend: [TrendPoint] = []
    var calibration: [CalibrationBin] = []
    var calibrationBias: Double?
    var brierScore: Double?
    var activity: [DayActivity] = []
    var activeDays30 = 0
    var minutesTotal: Double = 0
    var minutes7: Double = 0
    var errorBreakdown: [(ErrorCategory, Int)] = []
    var buckets: [(KnowledgeBucket, SuccessTally)] = []
    var pretestBefore: Double?
    var pretestAfter: Double?
    var pretestCount = 0
    var mastery: [MasteryPoint] = []
    var delayedRecall: SuccessTally = SuccessTally()
}

/// All dashboard numbers. Measured values come from review logs; predicted values come
/// from FSRS and are labelled as model estimates everywhere in the UI.
enum AnalyticsEngine {
    static func averageSecondsPerReview(logs: [ReviewLog]) -> Double {
        let recent = logs.suffix(200).map(\.responseSeconds).filter { $0 > 1 && $0 < 600 }
        guard recent.count >= 5 else { return 40 }
        return min(180, max(10, recent.reduce(0, +) / Double(recent.count) + 10))
    }

    static func compute(db: AppDatabase, scheduler: FSRSScheduler, now: Date, calendar: Calendar = .current) -> AnalyticsSnapshot {
        var s = AnalyticsSnapshot()
        let scheduledLogs = db.reviewLogs.filter(\.countedForScheduling)
        let introduced = db.items.filter(\.isIntroduced)

        s.totalItems = db.items.count
        s.learnedItems = introduced.count
        s.successfulRetrievals = scheduledLogs.filter { $0.outcome == .correct }.count
        s.partialRetrievals = scheduledLogs.filter { $0.outcome == .partial }.count
        s.failedRetrievals = scheduledLogs.filter { $0.outcome.isFailure }.count

        let since30 = now.addingTimeInterval(-30 * 86_400)
        let last30 = scheduledLogs.filter { $0.date >= since30 }
        if !last30.isEmpty {
            s.measuredRecall30 = Double(last30.filter { $0.outcome == .correct }.count) / Double(last30.count)
        }
        let reviewItems = introduced.filter { $0.card.state == .review }
        if !reviewItems.isEmpty {
            s.predictedRetentionNow = reviewItems.map { scheduler.retrievability(of: $0.card, at: now) }.reduce(0, +) / Double(reviewItems.count)
        }

        let today = calendar.startOfDay(for: now)
        let active = introduced.filter { !$0.isSuspended }
        s.overdue = active.filter { $0.card.due < today }.count
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            s.dueToday = active.filter { $0.card.due < tomorrow }.count
        }
        s.upcoming = (0..<14).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let count = active.filter { offset == 0 ? $0.card.due < next : ($0.card.due >= day && $0.card.due < next) }.count
            return DayCount(day: day, count: count)
        }

        for state in MemoryState.allCases { s.stateCounts[state] = 0 }
        for item in db.items {
            s.stateCounts[MemoryStateClassifier.state(of: item, scheduler: scheduler, now: now), default: 0] += 1
        }

        s.subjects = db.subjects.map { subject in
            let items = db.items.filter { $0.subjectID == subject.id }
            let ids = Set(items.map(\.id))
            let logs = last30.filter { ids.contains($0.itemID) }
            let reviewed = items.filter { $0.card.state == .review }
            return SubjectStat(id: subject.id, name: subject.name, items: items.count,
                               measuredRecall: logs.isEmpty ? nil : Double(logs.filter { $0.outcome == .correct }.count) / Double(logs.count),
                               predictedRetention: reviewed.isEmpty ? nil : reviewed.map { scheduler.retrievability(of: $0.card, at: now) }.reduce(0, +) / Double(reviewed.count),
                               attempts: logs.count)
        }

        s.trend = weeklyTrend(logs: scheduledLogs, now: now, weeks: 12, calendar: calendar)

        let confidenceLogs = db.reviewLogs.filter { $0.confidence != nil && $0.date >= now.addingTimeInterval(-90 * 86_400) }
        s.calibration = CalibrationAnalyzer.bins(from: confidenceLogs)
        s.calibrationBias = CalibrationAnalyzer.bias(from: confidenceLogs)
        s.brierScore = CalibrationAnalyzer.brierScore(from: confidenceLogs)

        s.activity = (0..<30).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let logs = db.reviewLogs.filter { calendar.isDate($0.date, inSameDayAs: day) }
            return DayActivity(day: day, reviews: logs.count, minutes: logs.map(\.responseSeconds).reduce(0, +) / 60)
        }
        s.activeDays30 = s.activity.filter { $0.reviews > 0 }.count
        s.minutesTotal = (db.sessions.map(\.durationSeconds).reduce(0, +)) / 60
        let since7 = now.addingTimeInterval(-7 * 86_400)
        s.minutes7 = db.sessions.filter { $0.startedAt >= since7 }.map(\.durationSeconds).reduce(0, +) / 60

        var errors: [ErrorCategory: Int] = [:]
        for log in db.reviewLogs { if let c = log.errorCategory { errors[c, default: 0] += 1 } }
        s.errorBreakdown = ErrorCategory.allCases.compactMap { c in errors[c].map { (c, $0) } }.sorted { $0.1 > $1.1 }

        s.buckets = KnowledgeBucket.allCases.map { bucket in
            let rows = scheduledLogs.filter { $0.exerciseType.bucket == bucket }
            return (bucket, SuccessTally(attempts: rows.count, successes: rows.filter { $0.outcome == .correct }.count))
        }

        let delayed = scheduledLogs.filter { $0.elapsedDays >= ReviewProcessor.delayedRecallDays }
        s.delayedRecall = SuccessTally(attempts: delayed.count, successes: delayed.filter { $0.outcome == .correct }.count)

        let pre = db.pretests.filter { $0.phase == .pre }
        let post = db.pretests.filter { $0.phase == .post }
        let pairedIDs = Set(pre.map(\.itemID)).intersection(post.map(\.itemID))
        if !pairedIDs.isEmpty {
            let preScores = pre.filter { pairedIDs.contains($0.itemID) }.map(\.score)
            let postScores = post.filter { pairedIDs.contains($0.itemID) }.map(\.score)
            s.pretestBefore = preScores.reduce(0, +) / Double(max(1, preScores.count))
            s.pretestAfter = postScores.reduce(0, +) / Double(max(1, postScores.count))
            s.pretestCount = pairedIDs.count
        }

        s.mastery = masteryProgression(logs: scheduledLogs, now: now, weeks: 12, calendar: calendar)
        return s
    }

    static func weekStart(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func weeklyTrend(logs: [ReviewLog], now: Date, weeks: Int, calendar: Calendar) -> [TrendPoint] {
        let currentWeek = weekStart(now, calendar: calendar)
        return (0..<weeks).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            // Only reviews of already-learned items: the first exposure has no prediction.
            let rows = logs.filter { $0.date >= start && $0.date < end && $0.stabilityBefore > 0 }
            guard !rows.isEmpty else { return nil }
            let measured = Double(rows.filter { $0.outcome == .correct }.count) / Double(rows.count)
            let predicted = rows.map(\.retrievabilityBefore).reduce(0, +) / Double(rows.count)
            return TrendPoint(weekStart: start, measuredRecall: measured, predictedRecall: predicted, reviews: rows.count)
        }
    }

    /// Cumulative number of items that reached the successive-relearning criterion
    /// (correct on 3 separate days), by week.
    static func masteryProgression(logs: [ReviewLog], now: Date, weeks: Int, calendar: Calendar) -> [MasteryPoint] {
        var correctDays: [UUID: [Date]] = [:]
        for log in logs.sorted(by: { $0.date < $1.date }) where log.outcome == .correct {
            let day = calendar.startOfDay(for: log.date)
            var days = correctDays[log.itemID] ?? []
            if !days.contains(day) { days.append(day) }
            correctDays[log.itemID] = days
        }
        let reachedDates = correctDays.values.compactMap { $0.count >= MemoryStateClassifier.masterySessions ? $0[MemoryStateClassifier.masterySessions - 1] : nil }
        let currentWeek = weekStart(now, calendar: calendar)
        return (0..<weeks).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            return MasteryPoint(weekStart: start, cumulative: reachedDates.filter { $0 < end }.count)
        }
    }

    /// Simple consistency score: share of the last 30 days with at least one review.
    static func consistency(_ snapshot: AnalyticsSnapshot) -> Double {
        Double(snapshot.activeDays30) / 30
    }
}
