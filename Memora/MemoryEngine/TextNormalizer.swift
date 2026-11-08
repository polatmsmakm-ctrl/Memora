import Foundation

/// Language-aware text normalisation for Arabic and English, used for offline grading,
/// grounding checks and content analysis.
enum TextNormalizer {
    static let englishStopwords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "being", "of", "in", "on", "at", "to",
        "for", "and", "or", "it", "its", "this", "that", "these", "those", "with", "as", "by", "from",
        "which", "what", "who", "whom", "into", "than", "then", "there", "their", "they", "them", "has",
        "have", "had", "do", "does", "did", "not", "no", "but", "if", "so", "such", "can", "could", "will",
        "would", "should", "may", "might", "also", "very", "more", "most", "some", "any", "each", "about",
        "i", "you", "he", "she", "we", "my", "your", "our", "his", "her"
    ]

    /// Arabic stopwords in *normalised* form (ة→ه, ى→ي, أ/إ/آ→ا).
    static let arabicStopwords: Set<String> = [
        "في", "من", "الي", "علي", "عن", "ان", "او", "و", "ثم", "هو", "هي", "هذا", "هذه", "ذلك", "تلك",
        "التي", "الذي", "الذين", "كان", "كانت", "يكون", "تكون", "مع", "ما", "لا", "لم", "لن", "قد", "كل",
        "بعض", "بين", "عند", "حتي", "اذا", "هم", "به", "بها", "له", "لها", "لهم", "فيه", "فيها", "منه",
        "منها", "عليه", "عليها", "او", "ام", "بل", "لكن", "كما", "ايضا", "غير", "اي", "وهو", "وهي", "تم", "يتم"
    ]

    // MARK: Normalisation

    static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        let space = Unicode.Scalar(UInt8(32))
        for u in text.lowercased().unicodeScalars {
            switch u.value {
            case 0x064B...0x065F, 0x0670, 0x0640:
                continue // harakat, superscript alef, tatweel
            case 0x0622, 0x0623, 0x0625, 0x0671:
                scalars.append(scalar(0x0627)) // alef variants → ا
            case 0x0649:
                scalars.append(scalar(0x064A)) // ى → ي
            case 0x0629:
                scalars.append(scalar(0x0647)) // ة → ه
            case 0x0624:
                scalars.append(scalar(0x0648)) // ؤ → و
            case 0x0626:
                scalars.append(scalar(0x064A)) // ئ → ي
            case 0x0660...0x0669:
                scalars.append(scalar(u.value - 0x0660 + 0x30))
            case 0x06F0...0x06F9:
                scalars.append(scalar(u.value - 0x06F0 + 0x30))
            default:
                if CharacterSet.punctuationCharacters.contains(u) || CharacterSet.symbols.contains(u) {
                    scalars.append(space)
                } else {
                    scalars.append(u)
                }
            }
        }
        let folded = String(scalars).folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func scalar(_ value: UInt32) -> Unicode.Scalar {
        Unicode.Scalar(value) ?? Unicode.Scalar(UInt8(32))
    }

    static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    static func isStopword(_ token: String) -> Bool {
        englishStopwords.contains(token) || arabicStopwords.contains(token)
    }

    /// Normalised, stop-word-free, lightly stemmed tokens.
    static func contentTokens(_ text: String) -> [String] {
        tokens(text).filter { !isStopword($0) && ($0.count > 1 || $0.allSatisfy(\.isNumber)) }.map(stem)
    }

    static func stem(_ token: String) -> String {
        guard let first = token.unicodeScalars.first else { return token }
        let isArabic = (0x0600...0x06FF).contains(first.value)
        if isArabic {
            for prefix in ["وال", "بال", "كال", "فال", "لل", "ال"] where token.hasPrefix(prefix) {
                let rest = String(token.dropFirst(prefix.count))
                if rest.count >= 3 { return rest }
            }
            if token.count > 4, token.hasSuffix("ات") || token.hasSuffix("ون") || token.hasSuffix("ين") {
                return String(token.dropLast(2))
            }
            return token
        }
        for suffix in ["ing", "ies", "es", "ed", "s"] where token.count > suffix.count + 3 && token.hasSuffix(suffix) {
            return String(token.dropLast(suffix.count))
        }
        return token
    }

    // MARK: Similarity

    static func fuzzyEqual(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let minLength = min(a.count, b.count)
        guard minLength >= 5 else { return false }
        if abs(a.count - b.count) > 1 { return false }
        return levenshtein(a, b) <= 1
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[y.count]
    }

    /// Fraction of the claim's content tokens that also occur (fuzzily) in the reference.
    static func coverage(of claim: String, in reference: String) -> Double {
        let claimTokens = Set(contentTokens(claim))
        guard !claimTokens.isEmpty else { return 0 }
        let referenceTokens = Set(contentTokens(reference))
        let found = claimTokens.filter { token in
            referenceTokens.contains(token) || referenceTokens.contains { fuzzyEqual($0, token) }
        }
        return Double(found.count) / Double(claimTokens.count)
    }

    // MARK: Structure

    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ".!?؟؛\n".contains(ch) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 3 { result.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.count >= 3 { result.append(tail) }
        return result
    }

    /// Distinctive original-surface words from a text, longest first (used as key terms).
    static func keyTerms(from text: String, limit: Int) -> [String] {
        var seen = Set<String>()
        var terms: [(word: String, order: Int)] = []
        let words = text.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "،" || $0 == "." || $0 == "؛" })
        for (index, raw) in words.enumerated() {
            let word = String(raw).trimmingCharacters(in: .punctuationCharacters)
            let normalized = normalize(word)
            guard normalized.count >= 3, !isStopword(normalized), !seen.contains(stem(normalized)) else { continue }
            seen.insert(stem(normalized))
            terms.append((word, index))
        }
        let chosen = terms.sorted { $0.word.count == $1.word.count ? $0.order < $1.order : $0.word.count > $1.word.count }.prefix(limit)
        return chosen.sorted { $0.order < $1.order }.map(\.word)
    }

    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
