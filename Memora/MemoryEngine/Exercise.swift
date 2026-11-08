import Foundation

/// One concrete retrieval task shown to the learner. The expected answer is never
/// rendered before the learner submits an attempt.
struct Exercise: Identifiable, Hashable {
    var id: UUID = UUID()
    var itemID: UUID
    var type: ExerciseType
    var prompt: String
    var expectedAnswer: String
    var keyPoints: [String]
    var choices: [String] = []
    var correctChoiceIndex: Int? = nil
    var imageFileName: String? = nil
    var comparisonItemID: UUID? = nil
    var variantIndex: Int? = nil
    var isFollowUp: Bool = false
    var contextNote: String? = nil
}

/// SplitMix64 – small deterministic generator so sessions and tests are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    init(date: Date) {
        self.init(seed: UInt64(max(0, date.timeIntervalSince1970 * 1000)))
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Builds every supported exercise format from a learning item. When a format
/// cannot be built (no image, too few distractors…) it falls back to short answer.
enum ExerciseFactory {
    static let blank = "_____"

    static func make(_ requested: ExerciseType,
                     for item: LearningItem,
                     siblings: [LearningItem],
                     comparison: LearningItem? = nil,
                     focusPoints: [String] = [],
                     rng: inout SeededGenerator,
                     isFollowUp: Bool = false) -> Exercise {
        let type = canBuild(requested, item: item, siblings: siblings, comparison: comparison) ? requested : .shortAnswer
        var ex = Exercise(itemID: item.id, type: type, prompt: item.prompt, expectedAnswer: item.answer,
                          keyPoints: item.gradingPoints, isFollowUp: isFollowUp)
        switch type {
        case .freeRecall:
            ex.prompt = LF("ex.freeRecall", item.title)
            ex.expectedAnswer = [item.answer, item.explanation].filter { !$0.isEmpty }.joined(separator: "\n")
        case .shortAnswer:
            break
        case .question:
            let variants = item.promptVariants
            var choices = Array(variants.indices)
            if let last = item.profile.lastVariantIndex, choices.count > 1 { choices.removeAll { $0 == last } }
            let index = choices.randomElement(using: &rng) ?? 0
            ex.prompt = variants[index].prompt
            ex.expectedAnswer = variants[index].answer
            ex.variantIndex = index
        case .cloze:
            let (text, hidden) = clozeText(answer: item.answer, preferred: focusPoints.isEmpty ? item.gradingPoints : focusPoints)
            ex.prompt = item.prompt + "\n\n" + text
            ex.expectedAnswer = hidden
            ex.keyPoints = [hidden]
        case .multipleChoice:
            let pool = Array(Set(siblings.map(\.answer).filter { !$0.isEmpty && $0 != item.answer }))
                .sorted()
                .shuffled(using: &rng)
            var options = Array(pool.prefix(3)) + [item.answer]
            options.shuffle(using: &rng)
            ex.choices = options
            ex.correctChoiceIndex = options.firstIndex(of: item.answer)
        case .reverse:
            ex.prompt = LF("ex.reverse", item.answer)
            ex.expectedAnswer = item.title
            ex.keyPoints = [item.title]
        case .keyword:
            ex.prompt = LF("ex.keyword", item.title)
            ex.expectedAnswer = item.gradingPoints.joined(separator: "، ")
        case .explanation:
            ex.prompt = LF("ex.explanation", item.title)
            ex.expectedAnswer = item.explanation.isEmpty ? item.answer : item.explanation
        case .image:
            ex.prompt = L("ex.image")
            ex.imageFileName = item.imageFileName
            ex.expectedAnswer = item.title + " — " + item.answer
        case .elaboration:
            if let q = item.elaborations.randomElement(using: &rng) {
                ex.prompt = q.question
                ex.expectedAnswer = q.answer
                ex.keyPoints = TextNormalizer.keyTerms(from: q.answer, limit: 5)
            } else {
                ex.prompt = LF("ex.elaboration.why", item.answer)
                ex.expectedAnswer = item.explanation
                ex.keyPoints = TextNormalizer.keyTerms(from: item.explanation, limit: 5)
            }
        case .selfExplanation:
            ex.prompt = LF("ex.selfExplanation", item.title)
            ex.expectedAnswer = [item.answer, item.explanation].filter { !$0.isEmpty }.joined(separator: "\n")
        case .transferNear, .transferFar:
            let level: TransferLevel = type == .transferNear ? .near : .far
            let problems = item.transferProblems.filter { $0.level == level }
            let chosen = (problems.isEmpty ? item.transferProblems : problems).randomElement(using: &rng)
            if let chosen {
                ex.prompt = chosen.problem
                ex.expectedAnswer = chosen.solution
                ex.keyPoints = TextNormalizer.keyTerms(from: chosen.solution, limit: 5)
                ex.type = chosen.level == .near ? .transferNear : .transferFar
            }
        case .comparison:
            if let other = comparison {
                ex.prompt = LF("ex.comparison", item.title, other.title)
                ex.expectedAnswer = item.title + ": " + item.answer + "\n" + other.title + ": " + other.answer
                ex.keyPoints = Array(item.gradingPoints.prefix(2)) + Array(other.gradingPoints.prefix(2))
                ex.comparisonItemID = other.id
            }
        case .blindRecall:
            ex.prompt = LF("ex.blind", item.title)
            ex.expectedAnswer = [item.answer, item.explanation].filter { !$0.isEmpty }.joined(separator: "\n")
        case .restudy:
            ex.prompt = item.prompt
        case .palace:
            break
        }
        return ex
    }

    /// Method-of-loci walk: the cue is only the place on the route.
    static func makePalace(for item: LearningItem, locusName: String) -> Exercise {
        Exercise(itemID: item.id, type: .palace, prompt: LF("ex.palace", locusName),
                 expectedAnswer: item.title + " — " + item.answer,
                 keyPoints: [item.title] + Array(item.gradingPoints.prefix(3)),
                 contextNote: locusName)
    }

    static func canBuild(_ type: ExerciseType, item: LearningItem, siblings: [LearningItem], comparison: LearningItem?) -> Bool {
        switch type {
        case .question: return !item.promptVariants.isEmpty
        case .multipleChoice:
            return Set(siblings.map(\.answer).filter { !$0.isEmpty && $0 != item.answer }).count >= 2
        case .keyword: return item.gradingPoints.count >= 2
        case .image: return item.imageFileName != nil
        case .elaboration: return !item.elaborations.isEmpty || !item.explanation.isEmpty
        case .transferNear, .transferFar: return !item.transferProblems.isEmpty
        case .comparison: return comparison != nil
        case .reverse: return !item.answer.isEmpty && item.answer.count <= 280
        case .palace: return false
        default: return true
        }
    }

    /// Hides one key point inside the answer. Returns the gapped text and the hidden phrase.
    static func clozeText(answer: String, preferred: [String]) -> (String, String) {
        for point in preferred.sorted(by: { $0.count > $1.count }) {
            let trimmed = point.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2,
                  let range = answer.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            var text = answer
            text.replaceSubrange(range, with: blank)
            return (text, String(answer[range]))
        }
        let words = answer.split(separator: " ").map(String.init)
        guard let longest = words.filter({ !TextNormalizer.isStopword(TextNormalizer.normalize($0)) }).max(by: { $0.count < $1.count }),
              let range = answer.range(of: longest) else {
            return (blank, answer)
        }
        var text = answer
        text.replaceSubrange(range, with: blank)
        return (text, longest)
    }
}
