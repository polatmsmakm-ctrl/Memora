import Foundation
import SwiftUI
import UIKit

/// Import pipeline: extract text → (optional user correction) → analyse into learning
/// units (offline heuristics or AI with grounding checks) → user approves/edits → save
/// with references to the verbatim source.
@MainActor
final class ImportViewModel: ObservableObject {
    enum Stage: Equatable { case input, extracted, approve, finished }

    @Published var stage: Stage = .input
    @Published var subjectID: UUID?
    @Published var newSubjectName = ""
    @Published var pastedText = ""
    @Published var pastedTitle = ""
    @Published var pastedKind: SourceKind = .text
    @Published private(set) var document: ExtractedDocument?
    @Published var editableText = ""
    @Published var useAI = AIService.isAvailable
    @Published var attachImage = true
    @Published var maxUnits = 15
    @Published var units: [DraftUnit] = []
    @Published private(set) var relationships: [DraftRelationship] = []
    @Published var errorMessage: String?
    @Published private(set) var busyMessage: String?
    @Published private(set) var notice: String?
    @Published private(set) var savedItemIDs: [UUID] = []
    @Published private(set) var savedSubjectID: UUID?

    var isBusy: Bool { busyMessage != nil }
    var includedCount: Int { units.filter(\.include).count }

    init(subjectID: UUID?) {
        self.subjectID = subjectID
    }

    // MARK: Extraction

    func importFile(_ url: URL, language: AppLanguage) async {
        await run(L("import.busy.extracting")) {
            try await DocumentImporter.extract(from: url, speechLocale: language.speechLocaleIdentifier)
        }
    }

    func importImages(_ images: [UIImage], title: String) async {
        await run(L("import.busy.ocr")) {
            try await DocumentImporter.fromImages(images, title: title)
        }
    }

    func importAudio(_ url: URL, language: AppLanguage) async {
        await run(L("import.busy.transcribing")) {
            let text = try await SpeechTranscriber.transcribe(url: url, localeIdentifier: language.speechLocaleIdentifier)
            return DocumentImporter.fromText(text, title: L("import.voiceTitle") + " " + Formatters.date(Date(), time: .short), kind: .audio)
        }
    }

    func useText() {
        let text = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        let title = TextNormalizer.isBlank(pastedTitle) ? String(firstLine.prefix(60)) : pastedTitle
        setDocument(DocumentImporter.fromText(text, title: title, kind: pastedKind))
    }

    private func run(_ message: String, _ work: () async throws -> ExtractedDocument) async {
        busyMessage = message
        errorMessage = nil
        defer { busyMessage = nil }
        do {
            let extracted = try await work()
            setDocument(extracted)
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func setDocument(_ doc: ExtractedDocument) {
        document = doc
        editableText = doc.text
        stage = .extracted
        Haptics.success()
    }

    // MARK: Analysis

    func analyze(settings: AppSettings) async {
        guard var doc = document else { return }
        if editableText != doc.text {
            // The learner explicitly corrected the extracted text (e.g. OCR errors).
            doc.text = editableText
            doc.sections = StructureDetector.sections(from: editableText, pageNumber: nil)
            document = doc
        }
        notice = nil
        busyMessage = L("import.busy.analyzing")
        defer { busyMessage = nil }
        var result: AnalysisResult?
        if useAI && AIService.isAvailable {
            do {
                result = try await AIService.make(settings: settings).generateUnits(from: doc, maxUnits: maxUnits)
                if let r = result, r.units.contains(where: { !$0.include }) {
                    notice = L("import.notice.ungrounded")
                }
            } catch {
                notice = LF("import.notice.aiFallback", error.localizedDescription)
            }
        }
        let analysis: AnalysisResult
        if let aiResult = result, !aiResult.units.isEmpty {
            analysis = aiResult
        } else {
            analysis = ContentAnalyzer.analyze(doc, maxUnits: maxUnits)
        }
        units = analysis.units
        relationships = analysis.relationships
        if units.isEmpty {
            errorMessage = L("import.error.noUnits")
            return
        }
        stage = .approve
    }

    // MARK: Save

    func save(to store: MemoraStore) {
        guard let doc = document else { return }
        let resolvedSubjectID: UUID
        if let id = subjectID, store.subject(id) != nil {
            resolvedSubjectID = id
        } else {
            let name = TextNormalizer.isBlank(newSubjectName) ? doc.title : newSubjectName
            let subject = Subject(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            store.addSubject(subject)
            resolvedSubjectID = subject.id
        }

        let source = SourceDocument(subjectID: resolvedSubjectID, title: doc.title, kind: doc.kind, text: doc.text,
                                    sections: doc.sections, originalFileName: doc.originalFileName)
        store.addSource(source)

        var imageName: String?
        if attachImage, let data = doc.imageData, let image = UIImage(data: data) {
            imageName = ImageStore.save(image)
        }

        let approved = units.filter { $0.include && !TextNormalizer.isBlank($0.prompt) && !TextNormalizer.isBlank($0.answer) }
        var idsByTitle: [String: UUID] = [:]
        let now = Date()
        let items: [LearningItem] = approved.enumerated().map { offset, unit in
            var item = LearningItem(subjectID: resolvedSubjectID,
                                    kind: unit.kind,
                                    title: unit.title,
                                    prompt: unit.prompt,
                                    answer: unit.answer,
                                    keyPoints: unit.keyPoints,
                                    explanation: unit.explanation,
                                    examples: unit.examples,
                                    imageFileName: imageName,
                                    sourceReference: SourceReference(sourceID: source.id, sectionHeading: unit.sectionHeading,
                                                                     pageNumber: unit.pageNumber, quote: unit.sourceQuote),
                                    tags: unit.sectionHeading.map { [$0] } ?? [],
                                    origin: unit.origin,
                                    createdAt: now.addingTimeInterval(Double(offset) * 0.001))
            item.mnemonics = MnemonicGenerator.automatic(for: item).prefix(1).map { $0 }
            idsByTitle[TextNormalizer.normalize(unit.title)] = item.id
            return item
        }
        store.addItems(items)

        var links: [ConceptLink] = []
        for relation in relationships {
            guard let from = idsByTitle[TextNormalizer.normalize(relation.fromTitle)],
                  let to = idsByTitle[TextNormalizer.normalize(relation.toTitle)], from != to else { continue }
            links.append(ConceptLink(fromID: from, toID: to, kind: relation.kind, origin: .ai))
        }
        for unit in approved {
            guard let to = idsByTitle[TextNormalizer.normalize(unit.title)] else { continue }
            for prerequisite in unit.prerequisiteTitles {
                if let from = idsByTitle[TextNormalizer.normalize(prerequisite)], from != to {
                    links.append(ConceptLink(fromID: from, toID: to, kind: .prerequisite, origin: unit.origin))
                }
            }
        }
        // Drop prerequisite links that would create cycles.
        var accepted: [ConceptLink] = []
        for link in links {
            if link.kind == .prerequisite && accepted.contains(where: { $0.kind == .prerequisite && $0.fromID == link.toID && $0.toID == link.fromID }) { continue }
            accepted.append(link)
        }
        store.addLinks(accepted)
        store.saveNow()

        savedItemIDs = items.map(\.id)
        savedSubjectID = resolvedSubjectID
        stage = .finished
        Haptics.success()
    }

    func reset() {
        stage = .input
        document = nil
        editableText = ""
        units = []
        relationships = []
        pastedText = ""
        pastedTitle = ""
        errorMessage = nil
        notice = nil
    }
}
