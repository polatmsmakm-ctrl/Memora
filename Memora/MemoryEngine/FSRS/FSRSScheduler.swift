import Foundation

/// Deterministic Swift port of the FSRS-5 scheduler.
///
/// Reference: open-spaced-repetition/py-fsrs (v5 `Scheduler.review_card`) and the
/// FSRS algorithm wiki. Formulas:
///  - R(t,S)   = (1 + F·t/S)^D,  D = −0.5, F = 19/81  ⇒ R(S,S) = 0.9
///  - I(r,S)   = S/F · (r^(1/D) − 1)
///  - S0(G)    = w[G−1]
///  - D0(G)    = w4 − e^(w5·(G−1)) + 1
///  - D'       = w7·D0(4) + (1−w7)·(D + ΔD·(10−D)/9),  ΔD = −w6·(G−3)
///  - S'recall = S·(1 + e^w8·(11−D)·S^(−w9)·(e^(w10·(1−R))−1)·hard·easy)
///  - S'forget = min(w11·D^(−w12)·((S+1)^w13 − 1)·e^(w14·(1−R)),  S / e^(w17·w18))
///  - S'short  = S·e^(w17·(G−3+w18))  (same-day reviews; never decreases for Good/Easy)
///
/// No randomness (no interval fuzz) so every result is reproducible and unit-testable.
struct FSRSScheduler {
    static let decay: Double = -0.5
    static let factor: Double = 19.0 / 81.0
    static let minimumStability: Double = 0.001
    static let secondsPerDay: Double = 86_400

    let parameters: FSRSParameters

    init(parameters: FSRSParameters = FSRSParameters()) {
        self.parameters = parameters
    }

    private var w: [Double] {
        parameters.weights.count == FSRSParameters.weightCount && parameters.weights.allSatisfy({ $0.isFinite })
            ? parameters.weights : FSRSParameters.defaultWeights
    }

    private var desiredRetention: Double {
        min(max(parameters.desiredRetention, FSRSParameters.retentionRange.lowerBound), FSRSParameters.retentionRange.upperBound)
    }

    // MARK: Retrievability

    func elapsedDays(since date: Date?, to now: Date) -> Double {
        guard let date else { return 0 }
        return max(0, now.timeIntervalSince(date) / Self.secondsPerDay)
    }

    func retrievability(stability: Double, elapsedDays: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + Self.factor * max(0, elapsedDays) / stability, Self.decay)
    }

    /// Model prediction of recall probability now. 0 for items never reviewed.
    func retrievability(of card: FSRSCard, at now: Date) -> Double {
        guard card.state != .new, card.lastReview != nil else { return 0 }
        return retrievability(stability: card.stability, elapsedDays: elapsedDays(since: card.lastReview, to: now))
    }

    // MARK: Intervals

    func intervalDays(for stability: Double, desiredRetention retention: Double? = nil) -> Int {
        let r = retention ?? desiredRetention
        let raw = stability / Self.factor * (pow(r, 1 / Self.decay) - 1)
        guard raw.isFinite else { return parameters.maximumInterval }
        return min(max(Int(raw.rounded()), 1), max(parameters.maximumInterval, 1))
    }

    // MARK: Model components

    func initialStability(_ rating: Rating) -> Double {
        max(w[rating.rawValue - 1], Self.minimumStability)
    }

    func initialDifficulty(_ rating: Rating) -> Double {
        clampDifficulty(w[4] - exp(w[5] * Double(rating.rawValue - 1)) + 1)
    }

    func nextDifficulty(_ difficulty: Double, rating: Rating) -> Double {
        let delta = -w[6] * Double(rating.rawValue - 3)
        let damped = difficulty + delta * (10 - difficulty) / 9
        let reverted = w[7] * initialDifficulty(.easy) + (1 - w[7]) * damped
        return clampDifficulty(reverted)
    }

    func shortTermStability(_ stability: Double, rating: Rating) -> Double {
        var increase = exp(w[17] * (Double(rating.rawValue) - 3 + w[18]))
        if rating == .good || rating == .easy { increase = max(increase, 1) }
        return max(stability * increase, Self.minimumStability)
    }

    func recallStability(difficulty: Double, stability: Double, retrievability r: Double, rating: Rating) -> Double {
        let hardPenalty = rating == .hard ? w[15] : 1
        let easyBonus = rating == .easy ? w[16] : 1
        let growth = exp(w[8]) * (11 - difficulty) * pow(stability, -w[9]) * (exp((1 - r) * w[10]) - 1) * hardPenalty * easyBonus
        return max(stability * (1 + growth), Self.minimumStability)
    }

    func forgetStability(difficulty: Double, stability: Double, retrievability r: Double) -> Double {
        let longTerm = w[11] * pow(difficulty, -w[12]) * (pow(stability + 1, w[13]) - 1) * exp((1 - r) * w[14])
        let shortTerm = stability / exp(w[17] * w[18])
        return max(min(longTerm, shortTerm), Self.minimumStability)
    }

    func nextStability(difficulty: Double, stability: Double, retrievability r: Double, rating: Rating) -> Double {
        rating == .again
            ? forgetStability(difficulty: difficulty, stability: stability, retrievability: r)
            : recallStability(difficulty: difficulty, stability: stability, retrievability: r, rating: rating)
    }

    private func clampDifficulty(_ d: Double) -> Double { min(max(d, 1), 10) }

    // MARK: Review

    /// Applies one review. Pure function: same inputs → same output.
    func review(_ card: FSRSCard, rating: Rating, at now: Date) -> FSRSReviewOutcome {
        var c = card
        let elapsed = elapsedDays(since: card.lastReview, to: now)
        let rBefore = retrievability(of: card, at: now)

        if card.state == .new {
            c.stability = initialStability(rating)
            c.difficulty = initialDifficulty(rating)
            c.state = .learning
            c.step = 0
        } else if elapsed < 1 {
            c.stability = shortTermStability(card.stability, rating: rating)
            c.difficulty = nextDifficulty(card.difficulty, rating: rating)
        } else {
            c.stability = nextStability(difficulty: card.difficulty, stability: card.stability, retrievability: rBefore, rating: rating)
            c.difficulty = nextDifficulty(card.difficulty, rating: rating)
        }

        let interval: TimeInterval
        switch c.state {
        case .new, .learning:
            interval = applySteps(&c, rating: rating, steps: parameters.learningSteps)
        case .review:
            if rating == .again {
                c.lapses += 1
                if parameters.relearningSteps.isEmpty {
                    interval = days(intervalDays(for: c.stability))
                } else {
                    c.state = .relearning
                    c.step = 0
                    interval = parameters.relearningSteps[0]
                }
            } else {
                interval = days(intervalDays(for: c.stability))
            }
        case .relearning:
            interval = applySteps(&c, rating: rating, steps: parameters.relearningSteps)
        }

        c.reps += 1
        c.lastReview = now
        c.due = now.addingTimeInterval(interval)
        return FSRSReviewOutcome(card: c, interval: interval, elapsedDays: elapsed, retrievabilityBefore: rBefore)
    }

    /// Intervals each rating would produce right now (shown on grading buttons).
    func preview(_ card: FSRSCard, at now: Date) -> [Rating: TimeInterval] {
        var result: [Rating: TimeInterval] = [:]
        for rating in Rating.allCases {
            result[rating] = review(card, rating: rating, at: now).interval
        }
        return result
    }

    private func applySteps(_ c: inout FSRSCard, rating: Rating, steps: [Double]) -> TimeInterval {
        if steps.isEmpty || (c.step >= steps.count && rating != .again) {
            graduate(&c)
            return days(intervalDays(for: c.stability))
        }
        switch rating {
        case .again:
            c.step = 0
            return steps[0]
        case .hard:
            if c.step == 0 && steps.count == 1 { return steps[0] * 1.5 }
            if c.step == 0 { return (steps[0] + steps[1]) / 2 }
            return steps[min(c.step, steps.count - 1)]
        case .good:
            if c.step + 1 >= steps.count {
                graduate(&c)
                return days(intervalDays(for: c.stability))
            }
            c.step += 1
            return steps[c.step]
        case .easy:
            graduate(&c)
            return days(intervalDays(for: c.stability))
        }
    }

    private func graduate(_ c: inout FSRSCard) {
        c.state = .review
        c.step = 0
    }

    private func days(_ n: Int) -> TimeInterval { Double(n) * Self.secondsPerDay }
}

extension FSRSScheduler {
    func isDue(_ card: FSRSCard, at now: Date) -> Bool {
        card.state != .new && card.due <= now
    }
}
