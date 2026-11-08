import Foundation

/// FSRS memory state for one item. Only `FSRSScheduler` mutates these fields.
struct FSRSCard: Codable, Hashable {
    var state: CardState
    /// Index into learning/relearning steps while in an intra-day phase.
    var step: Int
    /// Days until retrievability drops to 90%.
    var stability: Double
    /// 1 (easy) ... 10 (hard).
    var difficulty: Double
    var due: Date
    var lastReview: Date?
    var reps: Int
    var lapses: Int

    init(due: Date = Date()) {
        state = .new
        step = 0
        stability = 0
        difficulty = 0
        self.due = due
        lastReview = nil
        reps = 0
        lapses = 0
    }
}

/// Result of a single scheduling decision.
struct FSRSReviewOutcome: Equatable {
    var card: FSRSCard
    /// Time until the next review, in seconds.
    var interval: TimeInterval
    /// Days between the previous review and this one.
    var elapsedDays: Double
    /// Model-predicted probability of recall at the moment of this review (before updating).
    var retrievabilityBefore: Double

    var scheduledDays: Double { interval / 86_400 }
}
