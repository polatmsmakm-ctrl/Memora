import SwiftUI
import PhotosUI

/// Create or edit a learning unit, including manual questions, image (dual coding),
/// alternative wordings and transfer problems.
struct ItemEditorView: View {
    @State var item: LearningItem
    var isNew: Bool
    @EnvironmentObject private var store: MemoraStore
    @Environment(\.dismiss) private var dismiss

    @State private var keyPointsText = ""
    @State private var examplesText = ""
    @State private var tagsText = ""
    @State private var photo: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var removeImage = false
    @State private var newVariantPrompt = ""
    @State private var newVariantAnswer = ""
    @State private var newProblem = ""
    @State private var newSolution = ""
    @State private var newProblemLevel: TransferLevel = .near
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L("editor.basics")) {
                    if isNew || store.db.subjects.count > 1 {
                        Picker(L("common.subject"), selection: $item.subjectID) {
                            ForEach(store.db.subjects) { Text($0.name).tag($0.id) }
                        }
                    }
                    Picker(L("editor.kind"), selection: $item.kind) {
                        ForEach(ItemKind.allCases) { Text($0.title).tag($0) }
                    }
                    TextField(L("editor.title"), text: $item.title)
                    TextField(L("editor.prompt"), text: $item.prompt, axis: .vertical).lineLimit(2...6)
                    TextField(L("editor.answer"), text: $item.answer, axis: .vertical).lineLimit(2...10)
                }
                Section {
                    TextField(L("editor.keyPoints"), text: $keyPointsText, axis: .vertical).lineLimit(2...8)
                } header: { Text(L("editor.keyPoints.header")) } footer: { Text(L("editor.keyPoints.footer")) }
                Section(L("editor.explanation")) {
                    TextField(L("editor.explanation.placeholder"), text: $item.explanation, axis: .vertical).lineLimit(3...12)
                    TextField(L("editor.examples"), text: $examplesText, axis: .vertical).lineLimit(2...8)
                    TextField(L("editor.tags"), text: $tagsText)
                }
                Section(L("editor.image")) {
                    if let preview = image ?? (removeImage ? nil : ImageStore.load(item.imageFileName)) {
                        Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 200)
                        Button(L("editor.image.remove"), role: .destructive) { image = nil; removeImage = true; photo = nil }
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(L("editor.image.choose"), systemImage: "photo")
                    }
                }
                Section(L("editor.variants")) {
                    ForEach(item.promptVariants) { variant in
                        VStack(alignment: .leading) {
                            Text(variant.prompt).font(.callout)
                            Text(variant.answer).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { item.promptVariants.remove(atOffsets: $0) }
                    TextField(L("editor.variant.prompt"), text: $newVariantPrompt, axis: .vertical)
                    TextField(L("editor.variant.answer"), text: $newVariantAnswer, axis: .vertical)
                    Button(L("editor.add")) {
                        item.promptVariants.append(PromptVariant(prompt: newVariantPrompt, answer: newVariantAnswer, origin: .user))
                        newVariantPrompt = ""
                        newVariantAnswer = ""
                    }
                    .disabled(TextNormalizer.isBlank(newVariantPrompt) || TextNormalizer.isBlank(newVariantAnswer))
                }
                Section(L("editor.transfer")) {
                    ForEach(item.transferProblems) { problem in
                        VStack(alignment: .leading) {
                            Text(problem.level.title).font(.caption).foregroundStyle(Theme.accent)
                            Text(problem.problem).font(.callout)
                        }
                    }
                    .onDelete { item.transferProblems.remove(atOffsets: $0) }
                    Picker(L("editor.transfer.level"), selection: $newProblemLevel) {
                        ForEach(TransferLevel.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField(L("editor.transfer.problem"), text: $newProblem, axis: .vertical)
                    TextField(L("editor.transfer.solution"), text: $newSolution, axis: .vertical)
                    Button(L("editor.add")) {
                        item.transferProblems.append(TransferProblem(level: newProblemLevel, problem: newProblem, solution: newSolution, origin: .user))
                        newProblem = ""
                        newSolution = ""
                    }
                    .disabled(TextNormalizer.isBlank(newProblem) || TextNormalizer.isBlank(newSolution))
                }
                if !validationMessage.isEmpty {
                    Section { Text(validationMessage).font(.footnote).foregroundStyle(Theme.warning) }
                }
            }
            .memoraScreen()
            .navigationTitle(isNew ? L("subject.addItem") : L("common.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.save")) { save() }.disabled(!validationMessage.isEmpty)
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: loadFields)
            .onChange(of: photo) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                        image = picked
                        removeImage = false
                    }
                }
            }
        }
    }

    private var validationMessage: String {
        if TextNormalizer.isBlank(item.title) { return L("editor.validation.title") }
        if TextNormalizer.isBlank(item.prompt) { return L("editor.validation.prompt") }
        if TextNormalizer.isBlank(item.answer) { return L("editor.validation.answer") }
        if !TextNormalizer.isBlank(item.answer) && TextNormalizer.normalize(item.prompt).contains(TextNormalizer.normalize(item.answer)) && item.answer.count > 3 {
            return L("editor.validation.leak")
        }
        return ""
    }

    private func loadFields() {
        guard !loaded else { return }
        loaded = true
        keyPointsText = item.keyPoints.joined(separator: "\n")
        examplesText = item.examples.joined(separator: "\n")
        tagsText = item.tags.joined(separator: ", ")
        if store.subject(item.subjectID) == nil, let first = store.db.subjects.first { item.subjectID = first.id }
    }

    private func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func save() {
        var result = item
        result.title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.prompt = result.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        result.answer = result.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        result.keyPoints = Array(lines(keyPointsText).prefix(8))
        result.examples = lines(examplesText)
        result.tags = tagsText.split(whereSeparator: { $0 == "," || $0 == "،" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if removeImage, let old = result.imageFileName {
            ImageStore.delete(old)
            result.imageFileName = nil
        }
        if let image, let name = ImageStore.save(image) {
            if let old = result.imageFileName { ImageStore.delete(old) }
            result.imageFileName = name
        }
        if isNew { result.origin = .user }
        if store.db.subjects.isEmpty {
            let subject = Subject(name: L("subject.default"))
            store.addSubject(subject)
            result.subjectID = subject.id
        }
        store.upsertItem(result)
        Haptics.success()
        dismiss()
    }
}
