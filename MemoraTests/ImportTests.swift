import XCTest
@testable import Memora

final class ImportTests: XCTestCase {
    // MARK: Text decoding

    func testDecodesUTF8WithAndWithoutBOM() {
        let text = "الخلية: وحدة الحياة"
        XCTAssertEqual(DocumentImporter.decodeText(Data(text.utf8)), text)
        XCTAssertEqual(DocumentImporter.decodeText(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)), text)
    }

    func testDecodesUTF16WithBOM() {
        let text = "Cell: unit of life"
        let data = text.data(using: .utf16)!
        XCTAssertEqual(DocumentImporter.decodeText(data), text)
    }

    func testDecodesWindowsArabic() {
        let arabic = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsArabic.rawValue)))
        let text = "الخلية"
        let data = text.data(using: arabic)!
        XCTAssertEqual(DocumentImporter.decodeText(data), text)
    }

    func testFromTextNormalizesLineEndings() {
        let doc = DocumentImporter.fromText("# Title\r\nLine one is long enough to be content.\r\n", title: "T", kind: .text)
        XCTAssertFalse(doc.text.contains("\r"))
    }

    // MARK: Structure

    func testUnwrapRejoinsWrappedPDFLines() {
        let lines = [
            "Photosynthesis is the process by which green",
            "plants convert light energy into chemical energy.",
            "• Short list item"
        ]
        let result = StructureDetector.unwrap(lines)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], "Photosynthesis is the process by which green plants convert light energy into chemical energy.")
    }

    func testUnwrapJoinsHyphenatedWords() {
        let result = StructureDetector.unwrap(["The light reactions take place in the thyla-", "koid membranes of chloroplasts."])
        XCTAssertEqual(result, ["The light reactions take place in the thylakoid membranes of chloroplasts."])
    }

    func testUnwrapKeepsShortLines() {
        let lines = ["apple - تفاحة", "book - كتاب", "pen - قلم"]
        XCTAssertEqual(StructureDetector.unwrap(lines), lines)
    }

    func testGlossaryLineIsNotHeading() {
        XCTAssertFalse(StructureDetector.isHeading("Mitochondria: powerhouse", next: String(repeating: "x", count: 80)))
        XCTAssertTrue(StructureDetector.isHeading("Chapter 2: Cells", next: String(repeating: "x", count: 80)))
    }

    // MARK: Local analysis

    func testVocabularyListBecomesUnits() {
        let doc = DocumentImporter.fromText("apple - تفاحة\nbook - كتاب\npen = قلم\n• window: نافذة", title: "Words", kind: .text)
        let result = ContentAnalyzer.analyze(doc, maxUnits: 10)
        let titles = Set(result.units.map(\.title))
        XCTAssertTrue(titles.isSuperset(of: ["apple", "book", "pen", "window"]), "\(titles)")
        XCTAssertTrue(result.units.contains { $0.title == "apple" && $0.kind == .vocabulary && $0.answer == "تفاحة" })
    }

    func testDefinitionAnswerSkipsLinkingWords() {
        let def = ContentAnalyzer.definition(in: "Photosynthesis is the process by which plants make food.")
        XCTAssertEqual(def?.term, "Photosynthesis")
        XCTAssertEqual(def?.meaning, "process by which plants make food")
        let arabic = ContentAnalyzer.definition(in: "الميتوكوندريا هي عضية تنتج معظم طاقة الخلية.")
        XCTAssertEqual(arabic?.term, "الميتوكوندريا")
        XCTAssertEqual(arabic?.meaning, "عضية تنتج معظم طاقة الخلية")
    }

    func testURLIsNotATerm() {
        XCTAssertNil(ContentAnalyzer.definition(in: "https://example.com/page"))
    }

    func testPlainProseProducesSeveralUnits() {
        let prose = """
        The heart pumps blood through a network of arteries and veins across the whole body.
        Red blood cells carry oxygen from the lungs to every tissue using haemoglobin molecules.
        White blood cells defend the body against infection by recognising foreign invaders.
        Platelets help the blood clot quickly when a vessel is damaged or cut open.
        """
        let doc = DocumentImporter.fromText(prose, title: "Blood", kind: .text)
        let result = ContentAnalyzer.analyze(doc, maxUnits: 10)
        XCTAssertGreaterThanOrEqual(result.units.count, 3)
        XCTAssertTrue(result.units.allSatisfy { !$0.sourceQuote.isEmpty })
    }

    // MARK: AI response parsing

    func testParsesBareArrayOfUnits() throws {
        let text = #"[{"title":"Cell","prompt":"What is a cell?","answer":"The basic unit of life","keyPoints":"basic unit | life"}]"#
        let dto = try AIResponseValidator.parseUnitsResponse(text)
        XCTAssertEqual(dto.units.count, 1)
        XCTAssertEqual(dto.units[0].keyPoints ?? [], ["basic unit", "life"])
    }

    func testSkipsMalformedUnitsInsteadOfFailing() throws {
        let text = """
        ```json
        {"units":[{"title":"Good","prompt":"Q?","answer":"A"},{"title":"Broken"}],
         "relationships":[{"from":"Good","to":"Other","kind":"related"},{"bad":true}]}
        ```
        """
        let dto = try AIResponseValidator.parseUnitsResponse(text)
        XCTAssertEqual(dto.units.map(\.title), ["Good"])
        XCTAssertEqual(dto.relationships?.count, 1)
    }

    func testAcceptsAlternateKeys() throws {
        let text = #"{"learningUnits":[{"concept":"Osmosis","question":"Define osmosis","answer":"Water moving across a membrane","source_quote":"x"}]}"#
        let dto = try AIResponseValidator.parseUnitsResponse(text)
        XCTAssertEqual(dto.units.first?.title, "Osmosis")
        XCTAssertEqual(dto.units.first?.prompt, "Define osmosis")
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try AIResponseValidator.parseUnitsResponse("sorry, I can't"))
    }

    func testStrongSupportCountsAsGroundedEvenWithMisquote() {
        let source = "Osmosis is the movement of water across a semi-permeable membrane from low to high solute concentration."
        let unit = UnitDTO(title: "Osmosis", kind: nil, prompt: "What is osmosis?",
                           answer: "movement of water across a semi-permeable membrane",
                           keyPoints: nil, explanation: nil, examples: nil,
                           sourceQuote: "Osmosis means water moves through membranes", section: nil, prerequisites: nil)
        let report = AIResponseValidator.validateUnit(unit, source: source)
        XCTAssertTrue(report.isGrounded)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testChunkingKeepsAllText() {
        let paragraph = String(repeating: "word ", count: 50)
        let text = Array(repeating: paragraph, count: 200).joined(separator: "\n")
        let chunks = AIService.chunk(text, size: 2000)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 2000 })
        XCTAssertEqual(chunks.joined(separator: "\n").count, text.count)
    }

    // MARK: OCR ordering

    func testOCRReadingOrderTopToBottom() {
        let lines = [
            OCRLine(text: "second", box: CGRect(x: 0.1, y: 0.5, width: 0.5, height: 0.05)),
            OCRLine(text: "first", box: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.05))
        ]
        XCTAssertEqual(OCRLayout.readingOrder(lines), "first\nsecond")
    }

    func testOCRRightToLeftWithinArabicRow() {
        let lines = [
            OCRLine(text: "الخلية", box: CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.05)),
            OCRLine(text: "وحدة", box: CGRect(x: 0.6, y: 0.5, width: 0.3, height: 0.05))
        ]
        XCTAssertEqual(OCRLayout.readingOrder(lines), "وحدة الخلية")
    }

    func testStringsForImportFixesExist() {
        for key in ["import.error.password", "import.error.convert", "import.notice.partialAI", "import.selectAll", "analyze.vocab.prompt"] {
            XCTAssertNotNil(StringsTable.all[key], key)
        }
    }
}
