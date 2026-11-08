import Foundation

struct AttemptInput {
    var exerciseType: ExerciseType
    var evaluation: AnswerEvaluation
    var confidence: ConfidenceLevel?
    var hintsUsed: Int
    var responseSeconds: Double
    var userAnswer: String
    var mode: StudyMode
    var sessionID: UUID
    var variantIndex: Int?
    /// Rating chosen by the learner; when nil the policy's suggestion is used.
    var overrideRating: Rating?
    var countsForScheduling: Bool
    var date: Date
}

struct AttemptResult {
    var item: LearningItem
    var log: ReviewLog
    var rating: Rating
    var errorCategory: ErrorCategory?
    var intervention: Intervention?
}

/// Applies one attempt to an item: classifies the error, picks the intervention,
/// runs FSRS and updates the separate memory profile. Pure and deterministic.
enum ReviewProcessor {
    static let delayedRecallDays: Double = 21
    static let historyLimit = 60

    static func process(item: LearningItem,
                        input: AttemptInput,
                        context: ClassificationContext,
                        scheduler: FSRSScheduler,
                        calendar: Calendar = .current) -> AttemptResult {
        let evaluation = input.evaluation
        let category = ErrorClassifier.classify(evaluation: evaluation,
                                                confidence: input.confidence,
                                                exerciseType: input.exerciseType,
                                                hintsUsed: input.hintsUsed,
                                                priorFailures: item.profile.failureCount,
                                                context: context)
        let intervention = category.map { InterventionPlanner.plan(for: $0, evaluation: evaluation, context: context) }
        let suggested = RatingPolicy.suggestedRating(evaluation: evaluation,
                                                     confidence: input.confidence,
                                                     hintsUsed: input.hintsUsed,
                                                     exerciseType: input.exerciseType,
                                                     responseSeconds: input.responseSeconds)
        let rating = input.overrideRating ?? suggested
        let now = input.date
        var updated = item
        let before = item.card

        var elapsed = scheduler.elapsedDays(since: before.lastReview, to: now)
        var retrievabilityBefore = scheduler.retrievability(of: before, at: now)
        var scheduledDays = 0.0

        if input.countsForScheduling {
            let outcome = scheduler.review(before, rating: rating, at: now)
            updated.card = outcome.card
            elapsed = outcome.elapsedDays
            retrievabilityBefore = outcome.retrievabilityBefore
            scheduledDays = outcome.scheduledDays
            if updated.introducedAt == nil { updated.introducedAt = now }
            updateProfile(&updated.profile, input: input, category: category, elapsed: elapsed,
                          wasInReview: before.state == .review, calendar: calendar)
            updated.updatedAt = now
        } else if input.mode == .pretest {
            updated.pretestedAt = now
            updated.updatedAt = now
        }

        let log = ReviewLog(itemID: item.id,
                            subjectID: item.subjectID,
                            sessionID: input.sessionID,
                            date: now,
                            mode: input.mode,
                            exerciseType: input.exerciseType,
                            outcome: evaluation.outcome,
                            score: evaluation.score,
                            rating: input.countsForScheduling ? rating : nil,
                            confidence: input.confidence,
                            hintsUsed: input.hintsUsed,
                            responseSeconds: input.responseSeconds,
                            errorCategory: category,
                            evaluationSource: evaluation.source,
                            countedForScheduling: input.countsForScheduling,
                            elapsedDays: elapsed,
                            retrievabilityBefore: retrievabilityBefore,
                            stabilityBefore: before.stability,
                            stabilityAfter: updated.card.stability,
                            difficultyAfter: updated.card.difficulty,
                            scheduledDays: scheduledDays,
                            userAnswer: String(input.userAnswer.prefix(2000)))
        return AttemptResult(item: updated, log: log, rating: rating, errorCategory: category, intervention: intervention)
    }

    private static func updateProfile(_ profile: inout MemoryProfile,
                                      input: AttemptInput,
                                      category: ErrorCategory?,
                                      elapsed: Double,
                                      wasInReview: Bool,
                                      calendar: Calendar) {
        let outcome = input.evaluation.outcome
        switch outcome {
        case .correct: profile.successCount += 1
        case .partial: profile.partialCount += 1
        case .incorrect, .noAnswer: profile.failureCount += 1
        }

        if let confidence = input.confidence {
            profile.confidenceHistory.append(ConfidenceSample(date: input.date, confidence: confidence, wasCorrect: outcome == .correct))
            if profile.confidenceHistory.count > historyLimit {
                profile.confidenceHistory.removeFirst(profile.confidenceHistory.count - historyLimit)
            }
        }

        if let category {
            profile.errorCounts[category.rawValue, default: 0] += 1
            profile.lastErrorCategory = category
        }

        if outcome == .correct {
            let day = calendar.startOfDay(for: input.date)
            if !profile.successfulSessionDays.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
                profile.successfulSessionDays.append(day)
            }
            if elapsed >= delayedRecallDays { profile.delayedRecallSuccesses += 1 }
        } else if outcome.isFailure && wasInReview {
            // Mastery is never permanent: a lapse resets the successive-relearning count.
            if MemoryStateClassifier.masterySessions <= profile.distinctSuccessfulDays {
                profile.masteryRevokedAt = input.date
            }
            profile.successfulSessionDays = []
        }

        profile.lastOutcomes.append(outcome)
        if profile.lastOutcomes.count > 6 { profile.lastOutcomes.removeFirst(profile.lastOutcomes.count - 6) }

        if !profile.sessionIDs.contains(input.sessionID) {
            profile.sessionIDs.append(input.sessionID)
            if profile.sessionIDs.count > historyLimit { profile.sessionIDs.removeFirst() }
        }

        let bucket = input.exerciseType.bucket.rawValue
        var tally = profile.bucketStats[bucket] ?? SuccessTally()
        tally.attempts += 1
        if outcome == .correct { tally.successes += 1 }
        profile.bucketStats[bucket] = tally

        profile.lastExerciseType = input.exerciseType
        if let variant = input.variantIndex { profile.lastVariantIndex = variant }
    }
}
