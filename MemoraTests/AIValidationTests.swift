import XCTest
@testable import Memora

final class AIValidationTests: XCTestCase {
    let source = """
    Photosynthesis is the process by which green plants convert light energy into chemical energy.
    It takes place in the chloroplasts and releases oxygen as a by-product.
    """

    func testJSONPayloadStripsMarkdownFences() throws {
        let text = "```json\n{\"verdict\":\"correct\",\"score\":0.9}\n```"
        let dto = try AIResponseValidator.decode(EvaluationDTO.self, from: text)
        XCTAssertEqual(dto.verdict, "correct")
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try AIResponseValidator.decode(EvaluationDTO.self, from: "not json"))
    }

    func testQuoteFoundVerbatimAndNormalized() {
        XCTAssertTrue(AIResponseValidator.quoteFound("It takes place in the chloroplasts", in: source))
        XCTAssertTrue(AIResponseValidator.quoteFound("it takes place in the chloroplasts and releases oxygen", in: source))
        XCTAssertFalse(AIResponseValidator.quoteFound("Photosynthesis happens in the mitochondria at night", in: source))
    }

    func testGroundedUnitAccepted() {
        let unit = UnitDTO(title: "Photosynthesis", kind: "definition", prompt: "What is photosynthesis?",
                           answer: "Plants convert light energy into chemical energy", keyPoints: ["light energy"],
                           explanation: nil, examples: nil,
                           sourceQuote: "Photosynthesis is the process by which green plants convert light energy into chemical energy.",
                           section: nil, prerequisites: nil)
        let report = AIResponseValidator.validateUnit(unit, source: source)
        XCTAssertTrue(report.isGrounded)
    }

    func testInventedUnitRejected() {
        let unit = UnitDTO(title: "Krebs cycle", kind: "process", prompt: "Describe the Krebs cycle",
                           answer: "Acetyl CoA enters the citric acid cycle producing NADH", keyPoints: nil,
                           explanation: nil, examples: nil, sourceQuote: "The Krebs cycle produces NADH.",
                           section: nil, prerequisites: nil)
        let report = AIResponseValidator.validateUnit(unit, source: source)
        XCTAssertFalse(report.isGrounded)
        XCTAssertFalse(report.issues.isEmpty)
    }

    func testDraftUnitsDeselectUngroundedAndDropUnknownRelationships() {
        let good = UnitDTO(title: "Photosynthesis", kind: "definition", prompt: "What is photosynthesis?",
                           answer: "Plants convert light energy into chemical energy", keyPoints: nil, explanation: nil, examples: nil,
                           sourceQuote: "green plants convert light energy into chemical energy", section: nil, prerequisites: nil)
        let bad = UnitDTO(title: "Invented", kind: "fact", prompt: "?", answer: "Moon is made of cheese",
                          keyPoints: nil, explanation: nil, examples: nil, sourceQuote: "cheese moon", section: nil, prerequisites: nil)
        let dto = UnitsResponseDTO(units: [good, bad, good],
                                   relationships: [RelationshipDTO(from: "Photosynthesis", to: "Unknown", kind: "related")])
        let result = AIResponseValidator.draftUnits(from: dto, source: source, maxUnits: 10)
        XCTAssertEqual(result.units.count, 2, "duplicates are removed")
        XCTAssertTrue(result.units[0].include)
        XCTAssertFalse(result.units[1].include)
        XCTAssertTrue(result.relationships.isEmpty)
    }

    func testEvaluationReconciliation() {
        let dto = EvaluationDTO(verdict: "correct", score: 0.2, correct: nil, missing: ["x"], incorrect: nil,
                                misconceptions: nil, errorCategory: "notACategory", confusedWith: " ", feedback: nil, rubric: nil)
        let evaluation = AIResponseValidator.evaluation(from: dto)
        XCTAssertEqual(evaluation.outcome, .partial)
        XCTAssertNil(evaluation.suggestedCategory)
        XCTAssertNil(evaluation.confusedWith)
        XCTAssertEqual(evaluation.source, .ai)
    }

    func testEvaluationScoreIsClamped() {
        let dto = EvaluationDTO(verdict: "partial", score: 3, correct: nil, missing: nil, incorrect: nil,
                                misconceptions: nil, errorCategory: "partialRecall", confusedWith: nil, feedback: "ok",
                                rubric: RubricDTO(accuracy: 2, completeness: -1, logic: 0.5, depth: nil))
        let evaluation = AIResponseValidator.evaluation(from: dto)
        XCTAssertEqual(evaluation.score, 1)
        XCTAssertEqual(evaluation.suggestedCategory, .partialRecall)
        XCTAssertEqual(evaluation.rubric?.accuracy, 1)
        XCTAssertEqual(evaluation.rubric?.completeness, 0)
    }

    func testEnrichmentRejectsRevealingHintsAndDriftingVariants() {
        let item = LearningItem(subjectID: UUID(), title: "Photosynthesis", prompt: "What is photosynthesis?",
                                answer: "Plants convert light energy into chemical energy")
        let dto = EnrichmentDTO(elaborations: nil, examples: ["A leaf in sunlight"], analogies: nil, transferProblems: nil,
                                promptVariants: [VariantDTO(prompt: "How do plants store sunlight?", answer: "They convert light energy into chemical energy"),
                                                 VariantDTO(prompt: "Unrelated?", answer: "Volcanoes erupt magma")],
                                hints: ["Plants convert light energy into chemical energy", "Think about leaves and the sun"])
        let enrichment = AIResponseValidator.enrichment(from: dto, item: item, sourceText: source)
        XCTAssertEqual(enrichment.promptVariants.count, 1)
        XCTAssertEqual(enrichment.hints, ["Think about leaves and the sun"])
        XCTAssertEqual(enrichment.rejectedCount, 2)
        XCTAssertTrue(enrichment.promptVariants.allSatisfy { $0.origin == .ai })
    }

    func testGeminiErrorMapping() {
        XCTAssertEqual(GeminiProvider.httpError(429), .rateLimited)
        XCTAssertEqual(GeminiProvider.httpError(404), .modelNotFound)
        XCTAssertEqual(GeminiProvider.httpError(403), .forbidden)
        XCTAssertEqual(GeminiProvider.httpError(500), .overloaded)
        XCTAssertEqual(GeminiProvider.httpError(418), .server(418))
    }

    func testGeminiTextExtraction() throws {
        let json = #"{"candidates":[{"content":{"parts":[{"text":"Hello "},{"text":"world"}]}}]}"#
        XCTAssertEqual(try GeminiProvider.extractText(from: Data(json.utf8)), "Hello world")
        let blocked = #"{"promptFeedback":{"blockReason":"SAFETY"}}"#
        XCTAssertThrowsError(try GeminiProvider.extractText(from: Data(blocked.utf8)))
    }

    func testModelSortingPrefersNewestFlash() {
        let sorted = GeminiProvider.sortedNewestFirst([
            AIModelInfo(id: "gemini-1.5-pro", displayName: ""),
            AIModelInfo(id: "gemini-2.0-flash", displayName: ""),
            AIModelInfo(id: "gemini-2.5-flash", displayName: "")
        ])
        XCTAssertEqual(sorted.first?.id, "gemini-2.5-flash")
    }

    func testContentAnalyzerProducesGroundedUnits() {
        let doc = DocumentImporter.fromText("""
        # Cell biology
        Mitochondria: the organelle that produces most of the cell's ATP through respiration.
        The nucleus is the organelle that stores the cell's genetic material.
        """, title: "Cells", kind: .text)
        let result = ContentAnalyzer.analyze(doc, maxUnits: 10)
        XCTAssertFalse(result.units.isEmpty)
        XCTAssertTrue(result.units.allSatisfy { $0.grounding?.isGrounded == true })
        XCTAssertTrue(result.units.contains { $0.title == "Mitochondria" && $0.kind == .definition })
    }
}
