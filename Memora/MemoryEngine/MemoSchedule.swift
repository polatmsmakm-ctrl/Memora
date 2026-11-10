import Foundation

/// The learner's fixed spaced schedule: each item is brought back after
/// 1 hour, then 1 day, 3 days, 1 week and 1.5 weeks. Reviewing it at the last step
/// marks it mastered and it stops coming back.
enum MemoSchedule {
    static let intervals: [TimeInterval] = [3_600, 86_400, 3 * 86_400, 7 * 86_400, 10.5 * 86_400]
    static var stepCount: Int { intervals.count }

    /// Starts (or restarts) the schedule: first reminder in one hour.
    static func start(_ item: inout LearningItem, kind: MemorizeType? = nil, now: Date = Date()) {
        item.memoStep = 0
        item.masteredAt = nil
        if let kind { item.memoKind = kind.rawValue }
        item.isSuspended = false
        if item.introducedAt == nil { item.introducedAt = now }
        // Out of the "new" state so reminders and review lists include it.
        if item.card.state == .new { item.card.state = .review }
        item.card.due = now.addingTimeInterval(intervals[0])
        item.updatedAt = now
    }

    /// Records a review. Remembered moves to the next interval (or mastery after the
    /// last one); forgotten goes back one step and repeats from there.
    /// Returns true when this review mastered the item.
    @discardableResult
    static func review(_ item: inout LearningItem, remembered: Bool, now: Date = Date()) -> Bool {
        let step = min(max(item.memoStep ?? 0, 0), stepCount - 1)
        if item.introducedAt == nil { item.introducedAt = now }
        if item.card.state == .new { item.card.state = .review }
        item.card.lastReview = now
        item.updatedAt = now
        if remembered {
            let next = step + 1
            if next >= stepCount {
                item.memoStep = stepCount
                item.masteredAt = now
                item.card.due = now.addingTimeInterval(365 * 86_400)
                return true
            }
            item.memoStep = next
            item.card.due = now.addingTimeInterval(intervals[next])
        } else {
            let back = max(0, step - 1)
            item.memoStep = back
            item.card.due = now.addingTimeInterval(intervals[back])
        }
        return false
    }

    static func isMastered(_ item: LearningItem) -> Bool { item.masteredAt != nil }

    /// Items following the schedule that are not mastered yet.
    static func isActive(_ item: LearningItem) -> Bool {
        item.masteredAt == nil && item.isIntroduced && !item.isSuspended
    }

    static func isDue(_ item: LearningItem, now: Date = Date()) -> Bool {
        isActive(item) && item.card.due <= now
    }

    /// Completed reviews shown as progress (0…stepCount).
    static func progress(_ item: LearningItem) -> Int {
        if item.masteredAt != nil { return stepCount }
        return min(max(item.memoStep ?? 0, 0), stepCount)
    }

    /// "This rule / poem / lesson is mastered" in the learner's words.
    static func masteredLabel(kind: String?, plural: Bool = false) -> String {
        switch MemorizeType(rawValue: kind ?? "") {
        case .rule: return L(plural ? "memo.mastered.rules" : "memo.mastered.rule")
        case .poem: return L("memo.mastered.poem")
        case .words: return L(plural ? "memo.mastered.words" : "memo.mastered.word")
        case .facts: return L("memo.mastered.lesson")
        default: return L("memo.mastered.item")
        }
    }
}

extension MemoSchedule {
    /// "1 hour", "1 day", "3 days", "1 week", "1.5 weeks" for the interval before step `step`.
    static func intervalName(_ step: Int) -> String {
        L("memo.interval.\(min(max(step, 0), stepCount - 1))")
    }
}
