import Foundation

// MARK: - Structured output DTOs

struct UnitDTO: Codable {
    var title: String
    var kind: String?
    var prompt: String
    var answer: String
    var keyPoints: [String]?
    var explanation: String?
    var examples: [String]?
    var sourceQuote: String?
    var section: String?
    var prerequisites: [String]?
}

struct RelationshipDTO: Codable {
    var from: String
    var to: String
    var kind: String
}

struct UnitsResponseDTO: Codable {
    var units: [UnitDTO]
    var relationships: [RelationshipDTO]?
}

struct RubricDTO: Codable {
    var accuracy: Double?
    var completeness: Double?
    var logic: Double?
    var depth: Double?
}

struct EvaluationDTO: Codable {
    var verdict: String
    var score: Double?
    var correct: [String]?
    var missing: [String]?
    var incorrect: [String]?
    var misconceptions: [String]?
    var errorCategory: String?
    var confusedWith: String?
    var feedback: String?
    var rubric: RubricDTO?
}

struct QADTO: Codable {
    var kind: String?
    var question: String
    var answer: String
}

struct TransferDTO: Codable {
    var level: String
    var problem: String
    var solution: String
}

struct VariantDTO: Codable {
    var prompt: String
    var answer: String
}

struct EnrichmentDTO: Codable {
    var elaborations: [QADTO]?
    var examples: [String]?
    var analogies: [String]?
    var transferProblems: [TransferDTO]?
    var promptVariants: [VariantDTO]?
    var hints: [String]?
}

struct MnemonicDTO: Codable {
    var content: String
    var explanation: String?
}

/// Validated enrichment ready to merge into an item (all AI content flagged `.ai`).
struct ItemEnrichment {
    var elaborations: [ElaborationQuestion]
    var examples: [String]
    var analogies: [String]
    var transferProblems: [TransferProblem]
    var promptVariants: [PromptVariant]
    var hints: [String]
    var rejectedCount: Int
}

// MARK: - Validation

/// Validates AI output before it can reach the learner: parses JSON safely, checks that
/// extracted units are supported by verbatim quotes from the source, rejects variants
/// that drift from the original meaning and hints that give the answer away.
enum AIResponseValidator {
    static let answerSupportThreshold = 0.6
    static let variantSupportThreshold = 0.5
    static let elaborationSupportThreshold = 0.35

    /// Strips Markdown fences and extracts the outermost JSON object.
    static func jsonPayload(from text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        }
        if let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}"), start < end {
            return String(t[start...end])
        }
        return t
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let data = jsonPayload(from: text).data(using: .utf8) else { throw AIError.invalidResponse }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIError.invalidResponse
        }
    }

    /// True when the quote occurs in the source (normalised), or a source window shares ≥85% of its tokens.
    static func quoteFound(_ quote: String, in source: String) -> Bool {
        let q = TextNormalizer.normalize(quote)
        guard q.count >= 8 else { return false }
        let s = TextNormalizer.normalize(source)
        if s.contains(q) { return true }
        let quoteTokens = TextNormalizer.tokens(quote)
        let sourceTokens = TextNormalizer.tokens(source)
        guard quoteTokens.count >= 3, sourceTokens.count >= quoteTokens.count else { return false }
        let needed = Set(quoteTokens)
        let window = quoteTokens.count
        var index = 0
        while index + window <= sourceTokens.count {
            let slice = Set(sourceTokens[index..<(index + window)])
            let overlap = Double(needed.intersection(slice).count) / Double(needed.count)
            if overlap >= 0.85 { return true }
            index += max(1, window / 3)
        }
        return false
    }

    static func validateUnit(_ unit: UnitDTO, source: String) -> GroundingReport {
        var issues: [String] = []
        let quote = unit.sourceQuote ?? ""
        let found = quoteFound(quote, in: source)
        if !found { issues.append(L("validation.quoteMissing")) }
        let support = TextNormalizer.coverage(of: unit.answer, in: source)
        if support < answerSupportThreshold { issues.append(L("validation.answerUnsupported")) }
        if TextNormalizer.isBlank(unit.prompt) || TextNormalizer.isBlank(unit.answer) { issues.append(L("validation.empty")) }
        return GroundingReport(supportScore: support, quoteFound: found, issues: issues)
    }

    static func draftUnits(from response: UnitsResponseDTO, source: String, maxUnits: Int) -> AnalysisResult {
        var seen = Set<String>()
        var units: [DraftUnit] = []
        for dto in response.units {
            let key = TextNormalizer.normalize(dto.title)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            let report = validateUnit(dto, source: source)
            let unit = DraftUnit(include: report.isGrounded,
                                 title: dto.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                 kind: ItemKind(rawValue: dto.kind ?? "") ?? .concept,
                                 prompt: dto.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                                 answer: dto.answer.trimmingCharacters(in: .whitespacesAndNewlines),
                                 keyPoints: (dto.keyPoints ?? []).filter { !TextNormalizer.isBlank($0) }.prefix(6).map { $0 },
                                 explanation: dto.explanation ?? "",
                                 examples: dto.examples ?? [],
                                 sourceQuote: dto.sourceQuote ?? "",
                                 sectionHeading: dto.section,
                                 prerequisiteTitles: dto.prerequisites ?? [],
                                 origin: .ai,
                                 grounding: report)
            units.append(unit)
            if units.count >= maxUnits { break }
        }
        let titles = Set(units.map { TextNormalizer.normalize($0.title) })
        let relationships = (response.relationships ?? []).compactMap { r -> DraftRelationship? in
            guard let kind = LinkKind(rawValue: r.kind),
                  titles.contains(TextNormalizer.normalize(r.from)),
                  titles.contains(TextNormalizer.normalize(r.to)) else { return nil }
            return DraftRelationship(fromTitle: r.from, toTitle: r.to, kind: kind)
        }
        return AnalysisResult(units: units, relationships: relationships)
    }

    static func evaluation(from dto: EvaluationDTO) -> AnswerEvaluation {
        let verdict = dto.verdict.lowercased()
        var score = min(max(dto.score ?? 0, 0), 1)
        var outcome: Outcome
        switch verdict {
        case "correct": outcome = .correct
        case "partial": outcome = .partial
        case "no_answer", "noanswer", "none": outcome = .noAnswer
        default: outcome = .incorrect
        }
        // Reconcile inconsistent verdict/score pairs conservatively.
        if outcome == .correct && score < 0.5 { outcome = .partial }
        if outcome == .incorrect && score >= 0.8 { outcome = .partial }
        if outcome == .noAnswer { score = 0 }
        if dto.score == nil { score = outcome.score }
        let rubric = dto.rubric.map {
            RubricScores(accuracy: clamp($0.accuracy), completeness: clamp($0.completeness),
                         logic: clamp($0.logic), depth: clamp($0.depth))
        }
        return AnswerEvaluation(outcome: outcome,
                                score: score,
                                matchedPoints: dto.correct ?? [],
                                missingPoints: dto.missing ?? [],
                                incorrectStatements: dto.incorrect ?? [],
                                misconceptions: dto.misconceptions ?? [],
                                feedback: dto.feedback ?? AnswerEvaluator.feedback(for: outcome, missing: dto.missing ?? []),
                                source: .ai,
                                suggestedCategory: dto.errorCategory.flatMap(ErrorCategory.init(rawValue:)),
                                confusedWith: dto.confusedWith.flatMap { TextNormalizer.isBlank($0) ? nil : $0 },
                                rubric: rubric)
    }

    private static func clamp(_ value: Double?) -> Double { min(max(value ?? 0, 0), 1) }

    static func enrichment(from dto: EnrichmentDTO, item: LearningItem, sourceText: String?) -> ItemEnrichment {
        let reference = [item.prompt, item.answer, item.explanation, item.keyPoints.joined(separator: " "), sourceText ?? ""].joined(separator: "\n")
        var rejected = 0

        let variants = (dto.promptVariants ?? []).compactMap { v -> PromptVariant? in
            guard !TextNormalizer.isBlank(v.prompt), TextNormalizer.coverage(of: v.answer, in: reference) >= variantSupportThreshold else {
                rejected += 1; return nil
            }
            return PromptVariant(prompt: v.prompt, answer: v.answer, origin: .ai)
        }
        let elaborations = (dto.elaborations ?? []).compactMap { q -> ElaborationQuestion? in
            guard !TextNormalizer.isBlank(q.question), TextNormalizer.coverage(of: q.answer, in: reference) >= elaborationSupportThreshold else {
                rejected += 1; return nil
            }
            return ElaborationQuestion(kind: ElaborationKind(rawValue: q.kind ?? "") ?? .why, question: q.question, answer: q.answer, origin: .ai)
        }
        let hints = (dto.hints ?? []).filter { hint in
            let ok = !TextNormalizer.isBlank(hint) && !HintGenerator.reveals(hint, answer: item.answer)
            if !ok { rejected += 1 }
            return ok
        }
        let transfers = (dto.transferProblems ?? []).compactMap { t -> TransferProblem? in
            guard !TextNormalizer.isBlank(t.problem), !TextNormalizer.isBlank(t.solution) else { rejected += 1; return nil }
            return TransferProblem(level: TransferLevel(rawValue: t.level) ?? .near, problem: t.problem, solution: t.solution, origin: .ai)
        }
        return ItemEnrichment(elaborations: Array(elaborations.prefix(5)),
                              examples: (dto.examples ?? []).filter { !TextNormalizer.isBlank($0) }.prefix(4).map { $0 },
                              analogies: (dto.analogies ?? []).filter { !TextNormalizer.isBlank($0) }.prefix(3).map { $0 },
                              transferProblems: Array(transfers.prefix(4)),
                              promptVariants: Array(variants.prefix(4)),
                              hints: Array(hints.prefix(3)),
                              rejectedCount: rejected)
    }
}
