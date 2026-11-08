import Foundation

/// Computes the learner-facing memory state from FSRS data plus the separate profile.
///
/// Long-term retention requires *successive relearning*: correct retrievals on at least
/// three different days, stability ≥ 21 days and a correct most-recent attempt. It is
/// recomputed on every call, so a later failure immediately revokes it.
enum MemoryStateClassifier {
    static let longTermStabilityDays: Double = 21
    static let masterySessions = 3
    static let weakRetrievability: Double = 0.7

    static func state(of item: LearningItem, scheduler: FSRSScheduler, now: Date) -> MemoryState {
        switch item.card.state {
        case .new:
            return item.introducedAt == nil ? .unseen : .new
        case .learning:
            return .learning
        case .relearning:
            return .relearning
        case .review:
            break
        }
        let r = scheduler.retrievability(of: item.card, at: now)
        let recent = item.profile.lastOutcomes.suffix(2)
        let twoRecentFailures = recent.count == 2 && recent.allSatisfy { $0.isFailure }
        if r < weakRetrievability || twoRecentFailures { return .weak }
        if isMastered(item) { return .longTerm }
        return .developing
    }

    static func isMastered(_ item: LearningItem) -> Bool {
        item.card.state == .review
            && item.card.stability >= longTermStabilityDays
            && item.profile.distinctSuccessfulDays >= masterySessions
            && item.profile.lastOutcomes.last == .correct
    }

    /// Progress towards the successive-relearning criterion (0...1).
    static func relearningProgress(_ item: LearningItem) -> Double {
        min(1, Double(item.profile.distinctSuccessfulDays) / Double(masterySessions))
    }
}
