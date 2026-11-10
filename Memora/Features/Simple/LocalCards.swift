import Foundation

/// Builds cards from what the learner wrote, without Gemini. A rule, poem or lesson is
/// one card (cue = its title, answer = the full text, kept exactly as written); words
/// become one card per line ("word - meaning").
enum LocalCards {
    static func build(type: MemorizeType, title rawTitle: String, text: String) -> GeneratedCardSet {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = body.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
        let given = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = given.isEmpty ? String(firstLine.prefix(50)) : given

        switch type {
        case .words:
            let cards = wordCards(from: body)
            return GeneratedCardSet(title: given.isEmpty ? L("memo.local.wordsTitle") : given, cards: cards, type: .words)
        case .poem:
            let cue = LF("memo.local.poemCue", title)
            return GeneratedCardSet(title: title, cards: [FlashcardDTO(front: cue, back: body)], type: .poem)
        case .rule:
            let cue = given.isEmpty ? LF("memo.local.ruleCue", short(firstLine)) : LF("memo.local.ruleCueNamed", given)
            return GeneratedCardSet(title: title, cards: [FlashcardDTO(front: cue, back: body)], type: .rule)
        case .facts, .auto:
            let cue = given.isEmpty ? LF("memo.local.lessonCue", short(firstLine)) : LF("memo.local.lessonCueNamed", given)
            return GeneratedCardSet(title: title, cards: [FlashcardDTO(front: cue, back: body)], type: .facts)
        }
    }

    /// "apple - تفاحة", "apple: تفاحة", "apple = تفاحة" or tab-separated; a line without a
    /// separator is kept as a card whose answer is the line itself.
    static func wordCards(from text: String) -> [FlashcardDTO] {
        let separators = [" - ", " – ", " — ", "\t", " = ", ": ", ":", "=", "-", "–"]
        var seen = Set<String>()
        return text.components(separatedBy: .newlines).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            for separator in separators {
                if let range = line.range(of: separator) {
                    let word = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                    let meaning = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    if !word.isEmpty && !meaning.isEmpty {
                        guard seen.insert(word.lowercased()).inserted else { return nil }
                        return FlashcardDTO(front: word, back: meaning)
                    }
                }
            }
            guard seen.insert(line.lowercased()).inserted else { return nil }
            return FlashcardDTO(front: line, back: line)
        }
    }

    /// The first few words, so the cue reminds without giving the whole thing away.
    private static func short(_ line: String) -> String {
        let words = line.split(separator: " ")
        return words.count <= 3 ? line : words.prefix(3).joined(separator: " ") + "…"
    }
}
