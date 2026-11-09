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

    /// Above this size the extracted text is shown read-only: a SwiftUI text editor with
    /// hundreds of thousands of characters freezes the interface.
    static let editableTextLimit = 20_000

    var isBusy: Bool { busyMessage != nil }
    var includedCount: Int { units.filter(\.include).count }
    var isTextEditable: Bool { (document?.text.count ?? 0) <= Self.editableTextLimit }

    private var workTask: Task<Void, Never>?

    init(subjectID: UUID?) {
        self.subjectID = subjectID
    }

    // MARK: Extraction

    func importFile(_ url: URL, language: AppLanguage) {
        let base = L("import.busy.extracting")
        run(base) { [weak self] in
            try await DocumentImporter.extract(from: url, speechLocale: language.speechLocaleIdentifier) { done, total in
                Task { @MainActor in self?.updateProgress(base, done, total) }
            }
        }
    }

    func importImages(_ images: [UIImage], title: String) {
        let base = L("import.busy.ocr")
        run(base) { [weak self] in
            try await DocumentImporter.fromImages(images, title: title) { done, total in
                Task { @MainActor in self?.updateProgress(base, done, total) }
            }
        }
    }

    func importAudio(_ url: URL, language: AppLanguage) {
        run(L("import.busy.transcribing")) {
            defer { try? FileManager.default.removeItem(at: url) }
            let text = try await SpeechTranscriber.transcribe(url: url, localeIdentifier: language.speechLocaleIdentifier)
            return DocumentImporter.fromText(text, title: L("import.voiceTitle") + " " + Formatters.date(Date(), time: .short), kind: .audio)
        }
    }

    func useText() {
        let text = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        UIApplication.shared.dismissKeyboard()
        let firstLine = text.components(separatedBy: .newlines).first { !TextNormalizer.isBlank($0) } ?? ""
        let title = TextNormalizer.isBlank(pastedTitle) ? String(firstLine.trimmingCharacters(in: .whitespaces).prefix(60)) : pastedTitle
        setDocument(DocumentImporter.fromText(text, title: title, kind: pastedKind))
    }

    func cancelWork() {
        workTask?.cancel()
        workTask = nil
        busyMessage = nil
    }

    private func updateProgress(_ base: String, _ done: Int, _ total: Int) {
        guard busyMessage != nil else { return }
        busyMessage = total > 1 ? base + "\n" + LF("import.busy.progress", done, total) : base
    }

    private func run(_ message: String, _ work: @escaping () async throws -> ExtractedDocument) {
        workTask?.cancel()
        busyMessage = message
        errorMessage = nil
        workTask = Task { [weak self] in
            do {
                let extracted = try await work()
                guard !Task.isCancelled else { return }
                self?.setDocument(extracted)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorMessage = error.localizedDescription
                Haptics.error()
            }
            self?.busyMessage = nil
        }
    }

    private func setDocument(_ doc: ExtractedDocument) {
        document = doc
        editableText = doc.text.count <= Self.editableTextLimit ? doc.text : ""
        if TextNormalizer.isBlank(newSubjectName) && subjectID == nil {
            newSubjectName = String(doc.title.prefix(60))
        }
        stage = .extracted
        Haptics.success()
    }

    // MARK: Analysis

    func analyze(settings: AppSettings) {
        guard var doc = document else { return }
        if isTextEditable && editableText != doc.text {
            // The learner explicitly corrected the extracted text (e.g. OCR errors).
            guard !TextNormalizer.isBlank(editableText) else { return }
            doc.text = editableText
            doc.sections = StructureDetector.sections(from: editableText, pageNumber: nil)
            document = doc
        }
        UIApplication.shared.dismissKeyboard()
        notice = nil
        errorMessage = nil
        busyMessage = L("import.busy.analyzing")
        let wantsAI = useAI && AIService.isAvailable
        let limit = maxUnits
        let service = AIService.make(settings: settings)
        let source = doc
        workTask?.cancel()
        workTask = Task { [weak self] in
            var notes: [String] = []
            var aiResult: AnalysisResult?
            if wantsAI {
                do {
                    let result = try await service.generateUnits(from: source, maxUnits: limit)
                    if let note = result.notice { notes.append(note) }
                    if result.units.contains(where: { $0.include }) {
                        aiResult = result
                        if result.units.contains(where: { !$0.include }) { notes.append(L("import.notice.ungrounded")) }
                    } else if !result.units.isEmpty {
                        notes.append(L("import.notice.noneGrounded"))
                    }
                } catch is CancellationError {
                    return
                } catch {
                    notes.append(LF("import.notice.aiFallback", error.localizedDescription))
                }
            }
            let analysis: AnalysisResult
            if let aiResult {
                analysis = aiResult
            } else {
                // Heavy text processing runs off the main thread so the interface stays responsive.
                analysis = await Task.detached(priority: .userInitiated) {
                    ContentAnalyzer.analyze(source, maxUnits: limit)
                }.value
            }
            guard !Task.isCancelled, let self else { return }
            self.busyMessage = nil
            self.units = analysis.units
            self.relationships = analysis.relationships
            self.notice = notes.isEmpty ? nil : notes.joined(separator: "\n")
            if analysis.units.isEmpty {
                self.errorMessage = L("import.error.noUnits")
                Haptics.error()
                return
            }
            self.stage = .approve
            Haptics.success()
        }
    }

    func setAllIncluded(_ include: Bool) {
        for index in units.indices { units[index].include = include }
        Haptics.selection()
    }

    func backToText() {
        stage = .extracted
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
        cancelWork()
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
