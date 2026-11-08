import Foundation

enum ExperimentMethod: String, Codable, CaseIterable, Identifiable {
    case activeRecall, rereading, freeRecall, multipleChoice, selfExplanation
    var id: String { rawValue }
    var title: String { L("experiment.method.\(rawValue)") }
    var exerciseType: ExerciseType {
        switch self {
        case .activeRecall: return .shortAnswer
        case .rereading: return .restudy
        case .freeRecall: return .freeRecall
        case .multipleChoice: return .multipleChoice
        case .selfExplanation: return .selfExplanation
        }
    }
}

enum ExperimentCondition: String, Codable, CaseIterable, Identifiable {
    case a, b
    var id: String { rawValue }
    var title: String { self == .a ? "A" : "B" }
}

enum ExperimentPhase: String, Codable {
    case practice, test
}

struct ExperimentPractice: Codable, Hashable {
    var date: Date
    var condition: ExperimentCondition
}

struct ExperimentTestResult: Codable, Hashable {
    var itemID: UUID
    var condition: ExperimentCondition
    var outcome: Outcome
    var score: Double
    var date: Date
}

/// A within-person comparison of two study methods on comparable material
/// followed by a delayed free-recall test. Results are descriptive only.
struct Experiment: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var hypothesis: String = ""
    var subjectID: UUID?
    var methodA: ExperimentMethod
    var methodB: ExperimentMethod
    var itemIDsA: [UUID]
    var itemIDsB: [UUID]
    var practiceSessionsPerCondition: Int = 2
    var testDelayDays: Int = 7
    var practices: [ExperimentPractice] = []
    var results: [ExperimentTestResult] = []
    var createdAt: Date = Date()

    func method(_ c: ExperimentCondition) -> ExperimentMethod { c == .a ? methodA : methodB }
    func itemIDs(_ c: ExperimentCondition) -> [UUID] { c == .a ? itemIDsA : itemIDsB }
    func practiceCount(_ c: ExperimentCondition) -> Int { practices.filter { $0.condition == c }.count }

    var allItemIDs: [UUID] { itemIDsA + itemIDsB }
    var isCompleted: Bool { !results.isEmpty }
    var practiceDone: Bool {
        practiceCount(.a) >= practiceSessionsPerCondition && practiceCount(.b) >= practiceSessionsPerCondition
    }
    var lastPracticeDate: Date? { practices.map(\.date).max() }
    var testAvailableDate: Date? {
        guard practiceDone, let last = lastPracticeDate else { return nil }
        return last.addingTimeInterval(Double(testDelayDays) * 86_400)
    }
    func isTestAvailable(now: Date = Date()) -> Bool {
        guard !isCompleted, let date = testAvailableDate else { return false }
        return now >= date
    }

    /// Mean test score per condition and the number of items it is based on.
    func summary(_ c: ExperimentCondition) -> (mean: Double, n: Int)? {
        let rows = results.filter { $0.condition == c }
        guard !rows.isEmpty else { return nil }
        return (rows.map(\.score).reduce(0, +) / Double(rows.count), rows.count)
    }
}
