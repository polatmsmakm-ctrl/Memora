import Foundation

/// High-level AI features. Everything here is optional: callers always have an
/// offline fallback, so the core memory system never depends on AI.
struct AIService {
    let provider: AIProvider
    let languageCode: String

    static let maxSourceCharactersPerRequest = 14_000

    static func make(settings: AppSettings) -> AIService {
        AIService(provider: GeminiProvider(model: settings.aiModel), languageCode: settings.language.rawValue)
    }

    static var isAvailable: Bool { AIKeyStore.hasKey }

    // MARK: Import

    /// Splits long sources into chunks to keep requests efficient, then merges and validates.
    static let maxChunksPerImport = 6

    /// Analyses up to `maxChunksPerImport` chunks. If a later chunk fails (e.g. the free
    /// quota runs out) the units already extracted are kept and a notice explains it.
    func generateUnits(from document: ExtractedDocument, maxUnits: Int) async throws -> AnalysisResult {
        let chunks = Self.chunk(document.text, size: Self.maxSourceCharactersPerRequest)
        let used = Array(chunks.prefix(Self.maxChunksPerImport))
        let perChunk = max(3, Int((Double(maxUnits) / Double(max(1, used.count))).rounded(.up)))
        var units: [DraftUnit] = []
        var relationships: [DraftRelationship] = []
        var notes: [String] = []
        if chunks.count > used.count {
            notes.append(LF("import.notice.partialAI", used.count * 100 / chunks.count))
        }
        for (index, chunk) in used.enumerated() {
            try Task.checkCancellation()
            let request = AIRequest(systemInstruction: AIPrompts.units(maxUnits: perChunk, language: languageCode),
                                    messages: [AIMessage(role: .user, text: "SOURCE:\n" + chunk)],
                                    jsonOutput: true,
                                    temperature: 0.2)
            let dto: UnitsResponseDTO
            do {
                let text = try await provider.generate(request)
                dto = try AIResponseValidator.parseUnitsResponse(text)
            } catch {
                if error is CancellationError || units.isEmpty { throw error }
                notes.append(LF("import.notice.aiStopped", index, used.count, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
                break
            }
            let result = AIResponseValidator.draftUnits(from: dto, source: chunk, maxUnits: perChunk)
            for unit in result.units where !units.contains(where: { TextNormalizer.normalize($0.title) == TextNormalizer.normalize(unit.title) }) {
                var located = unit
                if let section = document.sections.first(where: { AIResponseValidator.quoteFound(unit.sourceQuote, in: $0.text) }) {
                    located.sectionHeading = located.sectionHeading ?? section.heading
                    located.pageNumber = section.pageNumber
                }
                units.append(located)
            }
            relationships.append(contentsOf: result.relationships)
            if units.count >= maxUnits { break }
        }
        return AnalysisResult(units: Array(units.prefix(maxUnits)), relationships: relationships,
                              notice: notes.isEmpty ? nil : notes.joined(separator: "\n"))
    }

    /// Splits on paragraph boundaries. Lengths are tracked incrementally (String.count is
    /// O(n), so recomputing it per paragraph is quadratic on long books).
    static func chunk(_ text: String, size: Int) -> [String] {
        guard text.count > size else { return [text] }
        var chunks: [String] = []
        var current = ""
        var currentLength = 0
        for paragraph in text.components(separatedBy: "\n") {
            let length = paragraph.count
            if currentLength + length + 1 > size, !current.isEmpty {
                chunks.append(current)
                current = ""
                currentLength = 0
            }
            if length > size {
                var start = paragraph.startIndex
                while start < paragraph.endIndex {
                    let end = paragraph.index(start, offsetBy: size, limitedBy: paragraph.endIndex) ?? paragraph.endIndex
                    chunks.append(String(paragraph[start..<end]))
                    start = end
                }
            } else {
                if !current.isEmpty {
                    current += "\n"
                    currentLength += 1
                }
                current += paragraph
                currentLength += length
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: Evaluation

    func evaluate(answer: String, exercise: Exercise, item: LearningItem) async throws -> AnswerEvaluation {
        let explanationTypes: [ExerciseType] = [.explanation, .selfExplanation, .elaboration, .comparison]
        let isExplanation = explanationTypes.contains(exercise.type)
        let message = """
        QUESTION TYPE: \(exercise.type.rawValue)\(isExplanation ? " (explanation — fill the rubric)" : "")
        QUESTION: \(exercise.prompt)
        REFERENCE ANSWER: \(exercise.expectedAnswer)
        KEY POINTS: \(exercise.keyPoints.joined(separator: " | "))
        CONCEPT EXPLANATION (reference): \(item.explanation)
        LEARNER ANSWER: \(answer)
        """
        let request = AIRequest(systemInstruction: AIPrompts.evaluation(language: languageCode),
                                messages: [AIMessage(role: .user, text: message)],
                                jsonOutput: true,
                                temperature: 0.1)
        let text = try await provider.generate(request)
        let dto = try AIResponseValidator.decode(EvaluationDTO.self, from: text)
        return AIResponseValidator.evaluation(from: dto)
    }

    // MARK: Enrichment

    func enrich(item: LearningItem, sourceText: String?) async throws -> ItemEnrichment {
        let excerpt = String((sourceText ?? "").prefix(6000))
        let message = """
        UNIT TITLE: \(item.title)
        QUESTION: \(item.prompt)
        ANSWER: \(item.answer)
        KEY POINTS: \(item.keyPoints.joined(separator: " | "))
        EXPLANATION: \(item.explanation)
        SOURCE EXCERPT: \(excerpt)
        """
        let request = AIRequest(systemInstruction: AIPrompts.enrichment(language: languageCode),
                                messages: [AIMessage(role: .user, text: message)],
                                jsonOutput: true,
                                temperature: 0.5)
        let text = try await provider.generate(request)
        let dto = try AIResponseValidator.decode(EnrichmentDTO.self, from: text)
        return AIResponseValidator.enrichment(from: dto, item: item, sourceText: sourceText)
    }

    func mnemonic(for item: LearningItem, kind: MnemonicKind) async throws -> Mnemonic {
        let message = """
        UNIT: \(item.title)
        ANSWER: \(item.answer)
        KEY ELEMENTS (in order): \(item.gradingPoints.joined(separator: " | "))
        """
        let request = AIRequest(systemInstruction: AIPrompts.mnemonic(kind: kind, language: languageCode),
                                messages: [AIMessage(role: .user, text: message)],
                                jsonOutput: true,
                                temperature: 0.8)
        let text = try await provider.generate(request)
        let dto = try AIResponseValidator.decode(MnemonicDTO.self, from: text)
        guard !TextNormalizer.isBlank(dto.content) else { throw AIError.invalidResponse }
        return Mnemonic(kind: kind, content: dto.content, explanation: dto.explanation ?? "", origin: .ai)
    }

    // MARK: Coach

    func coachStream(history: [AIMessage], socratic: Bool, context: String) -> AsyncThrowingStream<String, Error> {
        var messages = history.suffix(20).map { $0 }
        if !context.isEmpty, let firstUser = messages.firstIndex(where: { $0.role == .user }) {
            messages[firstUser].text = "LEARNER CONTEXT:\n" + context + "\n\n" + messages[firstUser].text
        }
        let request = AIRequest(systemInstruction: AIPrompts.coach(socratic: socratic, language: languageCode),
                                messages: messages,
                                jsonOutput: false,
                                temperature: 0.6)
        return provider.stream(request)
    }
}

// MARK: Files attached in the coach

struct FlashcardDTO: Codable, Hashable {
    var front: String
    var back: String
    var example: String?
}

struct FlashcardSetDTO: Codable {
    var title: String?
    var cards: [FlashcardDTO]
}

extension AIService {
    /// Free-form chat about an attached file (extract text, summarise, questions…).
    func fileStream(history: [AIMessage], attachment: CoachAttachment) -> AsyncThrowingStream<String, Error> {
        var messages = Array(history.suffix(12))
        if let last = messages.indices.last, messages[last].role == .user, let text = attachment.extractedText {
            messages[last].text = "ATTACHED FILE «\(attachment.fileName)»:\n" + String(text.prefix(60_000)) + "\n\n" + messages[last].text
        }
        let request = AIRequest(systemInstruction: AIPrompts.fileAssistant(language: languageCode),
                                messages: messages,
                                attachments: attachment.inlineParts,
                                jsonOutput: false,
                                temperature: 0.2)
        return provider.stream(request)
    }

    /// Flashcards (or vocabulary cards) generated from the attached file.
    func flashcards(from attachment: CoachAttachment, words: Bool, instruction: String) async throws -> FlashcardSetDTO {
        var text = "Make the cards. Learner's request: " + instruction
        if let extracted = attachment.extractedText {
            text = "ATTACHED FILE «\(attachment.fileName)»:\n" + String(extracted.prefix(60_000)) + "\n\n" + text
        }
        let request = AIRequest(systemInstruction: AIPrompts.flashcards(words: words, maxCards: 60, language: languageCode),
                                messages: [AIMessage(role: .user, text: text)],
                                attachments: attachment.inlineParts,
                                jsonOutput: true,
                                temperature: 0.2)
        let raw = try await provider.generate(request)
        var set = try AIResponseValidator.decode(FlashcardSetDTO.self, from: raw)
        var seen = Set<String>()
        set.cards = set.cards.compactMap { card in
            let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = card.back.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty, seen.insert(TextNormalizer.normalize(front)).inserted else { return nil }
            let example = card.example?.trimmingCharacters(in: .whitespacesAndNewlines)
            return FlashcardDTO(front: front, back: back, example: (example?.isEmpty ?? true) ? nil : example)
        }
        return set
    }
}
