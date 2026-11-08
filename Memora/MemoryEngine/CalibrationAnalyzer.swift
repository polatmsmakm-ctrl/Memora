import Foundation

struct CalibrationBin: Identifiable, Hashable {
    var id: Int { level.rawValue }
    var level: ConfidenceLevel
    /// What the learner predicted (subjective probability).
    var expected: Double
    /// What was measured (proportion correct).
    var observed: Double
    var count: Int
}

enum CalibrationLabel: String {
    case overconfident, underconfident, wellCalibrated, insufficientData
    var title: String { L("calibration.\(rawValue)") }
}

/// Compares confidence given *before* feedback with actual correctness.
enum CalibrationAnalyzer {
    static let minimumSamples = 10
    static let tolerance = 0.1

    static func bins(from logs: [ReviewLog]) -> [CalibrationBin] {
        ConfidenceLevel.allCases.compactMap { level in
            let rows = logs.filter { $0.confidence == level }
            guard !rows.isEmpty else { return nil }
            let correct = rows.filter { $0.outcome == .correct }.count
            return CalibrationBin(level: level, expected: level.probability,
                                  observed: Double(correct) / Double(rows.count), count: rows.count)
        }
    }

    /// Mean confidence minus accuracy. Positive → overconfident.
    static func bias(from logs: [ReviewLog]) -> Double? {
        let rows = logs.filter { $0.confidence != nil }
        guard rows.count >= minimumSamples else { return nil }
        let meanConfidence = rows.compactMap { $0.confidence?.probability }.reduce(0, +) / Double(rows.count)
        let accuracy = Double(rows.filter { $0.outcome == .correct }.count) / Double(rows.count)
        return meanConfidence - accuracy
    }

    static func label(for bias: Double?) -> CalibrationLabel {
        guard let bias else { return .insufficientData }
        if bias > tolerance { return .overconfident }
        if bias < -tolerance { return .underconfident }
        return .wellCalibrated
    }

    /// Brier score of confidence judgements (0 = perfect).
    static func brierScore(from logs: [ReviewLog]) -> Double? {
        let rows = logs.compactMap { log -> Double? in
            guard let c = log.confidence else { return nil }
            let actual: Double = log.outcome == .correct ? 1 : 0
            return pow(c.probability - actual, 2)
        }
        guard rows.count >= minimumSamples else { return nil }
        return rows.reduce(0, +) / Double(rows.count)
    }
}
