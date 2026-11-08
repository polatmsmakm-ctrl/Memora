import Foundation

/// Progressive hints: each level gives more cue support without stating the answer.
/// Level 1 – a category/length cue (or the first authored hint),
/// Level 2 – first letters of each key term,
/// Level 3 – partially masked answer with roughly half of the words hidden.
enum HintGenerator {
    static func hints(for exercise: Exercise, item: LearningItem?) -> [String] {
        var result: [String] = []
        let authored = item?.hints.filter { !TextNormalizer.isBlank($0) && !reveals($0, answer: exercise.expectedAnswer) } ?? []
        if let first = authored.first {
            result.append(first)
        } else {
            let words = exercise.expectedAnswer.split(whereSeparator: { $0.isWhitespace }).count
            let kind = item?.kind.title ?? ""
            result.append(LF("hint.shape", kind, words))
        }
        let initials = exercise.keyPoints.prefix(5).compactMap { point -> String? in
            guard let firstWord = point.split(separator: " ").first else { return nil }
            return String(firstWord.prefix(2)) + "…"
        }
        if !initials.isEmpty {
            result.append(LF("hint.initials", initials.joined(separator: "  ")))
        }
        if authored.count > 1 {
            result.append(contentsOf: authored.dropFirst().prefix(1))
        }
        result.append(LF("hint.masked", masked(exercise.expectedAnswer)))
        return result
    }

    /// Hides every second content word.
    static func masked(_ text: String) -> String {
        var hide = false
        return text.split(separator: " ", omittingEmptySubsequences: false).map { raw -> String in
            let word = String(raw)
            let normalized = TextNormalizer.normalize(word)
            guard normalized.count >= 3, !TextNormalizer.isStopword(normalized) else { return word }
            hide.toggle()
            return hide ? String(repeating: "•", count: min(word.count, 6)) : word
        }.joined(separator: " ")
    }

    /// True when a hint would give the answer away (≥80% of answer terms present).
    static func reveals(_ hint: String, answer: String) -> Bool {
        let answerTokens = Set(TextNormalizer.contentTokens(answer))
        guard answerTokens.count >= 2 else {
            return !answerTokens.isEmpty && Set(TextNormalizer.contentTokens(hint)).isSuperset(of: answerTokens)
        }
        return TextNormalizer.coverage(of: answer, in: hint) >= 0.8
    }
}
