import Foundation

/// Parameters of the FSRS-5 model.
///
/// Default weights are the published FSRS-5 defaults from the open-spaced-repetition
/// project (py-fsrs / fsrs-rs). Users can paste personalised weights produced by the
/// official FSRS optimizer (e.g. from Anki) in Settings.
struct FSRSParameters: Codable, Equatable {
    static let defaultWeights: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575,
        0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621
    ]
    static let weightCount = 19
    static let retentionRange: ClosedRange<Double> = 0.70...0.97

    var weights: [Double] = FSRSParameters.defaultWeights
    var desiredRetention: Double = 0.9
    var maximumInterval: Int = 36_500
    /// Intra-day learning steps in seconds.
    var learningSteps: [Double] = [60, 600]
    var relearningSteps: [Double] = [600]

    var isValid: Bool {
        weights.count == Self.weightCount
            && weights.allSatisfy { $0.isFinite }
            && Self.retentionRange.contains(desiredRetention)
            && maximumInterval >= 1
    }

    /// Parses 19 comma/space separated numbers. Returns nil when invalid.
    static func parseWeights(_ text: String) -> [Double]? {
        let parts = text
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "،" })
            .map { String($0) }
            .filter { !$0.isEmpty }
        let values = parts.compactMap(Double.init)
        guard values.count == weightCount, values.count == parts.count, values.allSatisfy({ $0.isFinite }) else { return nil }
        return values
    }

    var weightsText: String {
        weights.map { String(format: "%.4f", $0) }.joined(separator: ", ")
    }
}

extension FSRSParameters {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FSRSParameters()
        self = d
        weights = c.decode(.weights, default: d.weights)
        desiredRetention = c.decode(.desiredRetention, default: d.desiredRetention)
        maximumInterval = c.decode(.maximumInterval, default: d.maximumInterval)
        learningSteps = c.decode(.learningSteps, default: d.learningSteps)
        relearningSteps = c.decode(.relearningSteps, default: d.relearningSteps)
    }
}
