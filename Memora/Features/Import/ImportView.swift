import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: ImportViewModel

    @State private var showFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showScanner = false
    @State private var showRecorder = false
    @State private var manualItem: LearningItem?
    @State private var textMode = false

    init(initialSubjectID: UUID?) {
        _vm = StateObject(wrappedValue: ImportViewModel(subjectID: initialSubjectID))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch vm.stage {
                case .input: inputStage
                case .extracted: extractedStage
                case .approve: ImportReviewView(vm: vm)
                case .finished: finishedStage
                }
            }
            .memoraScreen()
            .navigationTitle(L("import.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("common.close")) { dismiss() } }
                if vm.stage == .approve {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(LF("import.saveN", vm.includedCount)) { vm.save(to: store) }
                            .disabled(vm.includedCount == 0)
                    }
                }
            }
            .keyboardDoneButton()
            .overlay {
                if let message = vm.busyMessage {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(message).font(.callout)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .alert(L("common.error"), isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
                Button(L("common.ok"), role: .cancel) {}
            } message: { Text(vm.errorMessage ?? "") }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: DocumentImporter.importableTypes, allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await vm.importFile(url, language: store.settings.language) }
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var images: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { images.append(image) }
                    }
                    photoItems = []
                    if !images.isEmpty { await vm.importImages(images, title: L("import.photosTitle")) }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView(onFinish: { images in
                    showScanner = false
                    Task { await vm.importImages(images, title: L("import.scanTitle")) }
                }, onCancel: { showScanner = false })
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showRecorder) {
                VoiceRecorderSheet { url in
                    showRecorder = false
                    Task { await vm.importAudio(url, language: store.settings.language) }
                }
                .environment(\.layoutDirection, store.settings.language.layoutDirection)
            }
            .sheet(item: $manualItem) { item in
                ItemEditorView(item: item, isNew: true).environmentObject(store)
            }
        }
    }

    // MARK: Stages

    private var subjectPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("import.subject")).font(.subheadline.weight(.semibold))
            Picker(L("common.subject"), selection: $vm.subjectID) {
                Text(L("import.newSubject")).tag(UUID?.none)
                ForEach(store.db.subjects) { Text($0.name).tag(Optional($0.id)) }
            }
            .pickerStyle(.menu)
            if vm.subjectID == nil {
                TextField(L("import.newSubject.placeholder"), text: $vm.newSubjectName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var inputStage: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard { subjectPicker }
                if textMode {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("", selection: $vm.pastedKind) {
                                Text(SourceKind.text.title).tag(SourceKind.text)
                                Text(SourceKind.note.title).tag(SourceKind.note)
                            }
                            .pickerStyle(.segmented)
                            TextField(L("import.text.title"), text: $vm.pastedTitle).textFieldStyle(.roundedBorder)
                            AnswerEditor(text: $vm.pastedText, placeholder: L("import.text.placeholder"), minHeight: 220)
                            HStack {
                                Button(L("common.cancel")) { textMode = false }.buttonStyle(SecondaryButtonStyle(tint: .secondary))
                                Spacer()
                                Button(L("import.continue")) { vm.useText() }
                                    .buttonStyle(PrimaryButtonStyle())
                                    .disabled(TextNormalizer.isBlank(vm.pastedText))
                            }
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        sourceTile(L("import.src.text"), "text.alignleft") { textMode = true }
                        sourceTile(L("import.src.files"), "doc.richtext") { showFiles = true }
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                            tileLabel(L("import.src.photos"), "photo.on.rectangle")
                        }
                        .buttonStyle(.plain)
                        if DocumentScannerView.isSupported {
                            sourceTile(L("import.src.scan"), "doc.viewfinder") { showScanner = true }
                        }
                        sourceTile(L("import.src.voice"), "mic") { showRecorder = true }
                        sourceTile(L("import.src.manual"), "square.and.pencil") {
                            manualItem = LearningItem(subjectID: vm.subjectID ?? store.db.subjects.first?.id ?? UUID(),
                                                      title: "", prompt: "", answer: "")
                        }
                    }
                    Text(L("import.formats")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(Theme.padding)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    private func sourceTile(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(title, icon) }.buttonStyle(.plain)
    }

    private func tileLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 24, weight: .medium)).foregroundStyle(Theme.accent)
            Text(title).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private var extractedStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let doc = vm.document {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Chip(text: doc.kind.title, systemImage: doc.kind.systemImage)
                                Text(LF("import.sections", doc.sections.count)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(doc.title).font(.memoraTitle)
                            Text(LF("import.characters", doc.text.count)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    GlassCard { subjectPicker }
                    Text(L("import.preview")).font(.subheadline.weight(.semibold))
                    AnswerEditor(text: $vm.editableText, placeholder: "", minHeight: 240)
                    Text(L("import.preview.note")).font(.caption).foregroundStyle(.secondary)
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(L("import.useAI"), isOn: $vm.useAI).disabled(!AIService.isAvailable)
                            if !AIService.isAvailable {
                                Text(L("import.useAI.unavailable")).font(.caption).foregroundStyle(.secondary)
                            }
                            if doc.imageData != nil {
                                Toggle(L("import.attachImage"), isOn: $vm.attachImage)
                            }
                            Stepper(LF("import.maxUnits", vm.maxUnits), value: $vm.maxUnits, in: 3...40)
                            Text(L("import.maxUnits.note")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button(L("import.back")) { vm.reset() }.buttonStyle(SecondaryButtonStyle(tint: .secondary))
                        Spacer()
                        Button(L("import.analyze")) { Task { await vm.analyze(settings: store.settings) } }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(vm.isBusy || TextNormalizer.isBlank(vm.editableText))
                    }
                }
            }
            .padding(Theme.padding)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    private var finishedStage: some View {
        ScrollView {
            VStack(spacing: 16) {
                EmptyStateView(systemImage: "checkmark.circle", title: LF("import.done.title", vm.savedItemIDs.count), message: L("import.done.message"))
                if store.settings.pretestNewTopics {
                    Button {
                        let request = SessionRequest(mode: .pretest, subjectID: vm.savedSubjectID, itemIDs: Array(vm.savedItemIDs.prefix(10)))
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.start(request) }
                    } label: { Label(L("import.done.pretest"), systemImage: StudyMode.pretest.systemImage) }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: Theme.violet))
                }
                Button {
                    let request = SessionRequest(mode: .learn, subjectID: vm.savedSubjectID)
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.start(request) }
                } label: { Label(L("import.done.learn"), systemImage: "book") }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                Button(L("import.another")) { vm.reset() }.buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: .secondary))
            }
            .padding(Theme.padding)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}
