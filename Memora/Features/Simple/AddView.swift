import SwiftUI
import PhotosUI

/// The one place to add material. With Gemini on, it tidies the text into study cards;
/// with Gemini off, what the learner writes is saved as it is (files are read on the
/// device). Either way everything goes on the fixed reminder schedule.
struct AddView: View {
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter

    @AppStorage(AIService.enabledKey) private var aiEnabled = true
    @State private var type: MemorizeType = .auto
    @State private var title = ""
    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showScanner = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var result: GeneratedCardSet?
    @State private var work: Task<Void, Never>?
    @State private var startedAt = Date()
    @State private var receivedCards = 0
    @State private var reading = false
    @State private var activeModel: String?
    @State private var modelStartedAt = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if aiEnabled && !AIKeyStore.hasKey && result == nil && !busy {
                        noKeyCard
                    } else if busy {
                        busyCard
                    } else if result != nil {
                        resultSection
                    } else {
                        inputSection
                    }
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(Theme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Theme.padding)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .memoraScreen()
            .navigationTitle(L("add.title"))
            .keyboardDoneButton()
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                loadPhoto(item)
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView(onFinish: { images in
                    showScanner = false
                    if useAI {
                        run(name: L("add.scan.name")) { try CoachAttachment.fromImages(images, name: L("add.scan.name")) }
                    } else {
                        readLocally(name: L("add.scan.name")) { try await Self.ocr(images) }
                    }
                }, onCancel: { showScanner = false })
                .ignoresSafeArea()
            }
        }
    }

    private var useAI: Bool { aiEnabled && AIKeyStore.hasKey }

    /// Types offered: "auto" needs Gemini.
    private var types: [MemorizeType] { useAI ? MemorizeType.allCases : MemorizeType.allCases.filter { $0 != .auto } }

    // MARK: Sections

    private var inputSection: some View {
        VStack(spacing: 14) {
            Text(useAI ? L("add.intro") : L("add.intro.local"))
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(types) { option in
                        Button {
                            type = option
                            Haptics.selection()
                        } label: {
                            Label(option.title, systemImage: option.icon)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(type == option ? Theme.accent : Theme.accent.opacity(0.12), in: Capsule())
                                .foregroundStyle(type == option ? Color.white : Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(L(useAI ? "memo.type.\(type.rawValue).hint" : "memo.local.\(type.rawValue).hint"))
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            GlassCard {
                VStack(spacing: 10) {
                    if !useAI && type != .words {
                        TextField(L("memo.title.placeholder"), text: $title)
                            .textFieldStyle(.roundedBorder)
                    }
                    AnswerEditor(text: $text, placeholder: L("memo.placeholder.\(type.rawValue)"), minHeight: 160)
                    Button { useText() } label: {
                        Label(useAI ? L("memo.go") : L("memo.save"), systemImage: useAI ? "sparkles" : "tray.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(TextNormalizer.isBlank(text))
                }
            }

            Text(L("memo.orAttach")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                smallButton(L("add.file"), "doc.richtext") { pickFile() }
                PhotosPicker(selection: $photoItem, matching: .images) { smallLabel(L("add.photo"), "photo") }
                    .buttonStyle(.plain)
                if DocumentScannerView.isSupported {
                    smallButton(L("add.scan"), "doc.viewfinder") { showScanner = true }
                }
            }
        }
    }

    private func smallButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { smallLabel(title, icon) }.buttonStyle(.plain)
    }

    private func smallLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private var busyCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(reading ? L("add.busy.reading") : L("add.busy")).font(.callout).multilineTextAlignment(.center)
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    VStack(spacing: 4) {
                        if receivedCards > 0 {
                            Text(LF("add.busy.cards", receivedCards)).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                        Text(LF("add.busy.elapsed", Int(context.date.timeIntervalSince(startedAt))))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        if let activeModel {
                            Text(activeModel).font(.caption2).foregroundStyle(.tertiary)
                            if receivedCards == 0 && context.date.timeIntervalSince(modelStartedAt) > 12 {
                                Text(L("add.busy.waiting")).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                        }
                    }
                }
                Button(L("common.cancel")) {
                    work?.cancel()
                    busy = false
                }
                .buttonStyle(SecondaryButtonStyle(tint: .secondary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        FlashcardSetCard(cardSet: Binding(get: { result ?? GeneratedCardSet() }, set: { result = $0 }))
        if let result, result.saved {
            Button(L("add.another")) { reset() }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: .secondary))
        } else {
            Button(L("common.cancel")) { reset() }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: .secondary))
        }
    }

    private var noKeyCard: some View {
        VStack(spacing: 12) {
            EmptyStateView(systemImage: "sparkles", title: L("add.noKey.title"), message: L("add.noKey.message"),
                           actionTitle: L("add.noKey.action")) { router.selectedTab = .settings }
            Button(L("add.manual")) { aiEnabled = false }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: .secondary))
        }
    }

    // MARK: Actions

    private func reset() {
        work?.cancel()
        result = nil
        text = ""
        title = ""
        errorText = nil
        busy = false
    }

    private func pickFile() {
        UIApplication.shared.dismissKeyboard()
        let locale = store.settings.language.speechLocaleIdentifier
        let ai = useAI
        DocumentPicker.present { urls in
            guard let url = urls.first else { return }
            let name = url.deletingPathExtension().lastPathComponent
            if ai {
                run(name: name) { try await CoachAttachment.load(from: url, speechLocale: locale) }
            } else {
                readLocally(name: name) { try await DocumentImporter.extract(from: url, speechLocale: locale).text }
            }
        }
    }

    private func useText() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIApplication.shared.dismissKeyboard()
        if !useAI {
            result = LocalCards.build(type: type, title: title, text: trimmed)
            if result?.cards.isEmpty ?? true { result = nil; errorText = L("coach.cards.empty") }
            return
        }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? L("add.text.name")
        let name = String(firstLine.prefix(40))
        run(name: name) { CoachAttachment(fileName: name, systemImage: "text.alignleft", extractedText: trimmed) }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        if !useAI {
            readLocally(name: L("add.photo.name")) {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    throw ImportError.unreadable
                }
                return try await Self.ocr([image])
            }
            return
        }
        run(name: L("add.photo.name")) {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                throw ImportError.unreadable
            }
            return try CoachAttachment.fromImages([image], name: L("add.photo.name"))
        }
    }

    /// Without Gemini: reads the file/photo on the device and puts its text in the editor
    /// so the learner can trim it before saving.
    private func readLocally(name: String, _ read: @escaping () async throws -> String) {
        work?.cancel()
        errorText = nil
        busy = true
        reading = true
        startedAt = Date()
        activeModel = nil
        receivedCards = 0
        work = Task {
            do {
                let extracted = try await read().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !Task.isCancelled else { return }
                if extracted.isEmpty { throw ImportError.empty }
                text = extracted
                if title.isEmpty { title = name }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { errorText = error.localizedDescription }
            }
            busy = false
        }
    }

    static func ocr(_ images: [UIImage]) async throws -> String {
        var parts: [String] = []
        for image in images { parts.append(try await OCRService.recognizeText(in: image)) }
        return parts.joined(separator: "\n\n")
    }

    /// Prepares the attachment, asks Gemini for cards and shows the result to save.
    private func run(name: String, _ prepare: @escaping () async throws -> CoachAttachment) {
        work?.cancel()
        errorText = nil
        busy = true
        startedAt = Date()
        receivedCards = 0
        reading = true
        activeModel = nil
        let wantedType = type
        let service = AIService.make(settings: store.settings)
        work = Task {
            do {
                let attachment = try await prepare()
                reading = false
                let set = try await service.memorize(attachment, type: wantedType,
                                                     progress: { count in receivedCards = count },
                                                     model: { name in
                                                         if activeModel != nil && activeModel != name { receivedCards = 0 }
                                                         activeModel = name
                                                         modelStartedAt = Date()
                                                     })
                guard !Task.isCancelled else { return }
                if set.cards.isEmpty {
                    errorText = L("coach.cards.empty")
                } else {
                    let title = TextNormalizer.isBlank(set.title ?? "") ? name : (set.title ?? name)
                    let detected = wantedType == .auto ? (set.type.flatMap(MemorizeType.init(rawValue:)) ?? .facts) : wantedType
                    result = GeneratedCardSet(title: title, cards: set.cards, type: detected == .auto ? .facts : detected, note: set.note)
                    text = ""
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { errorText = error.localizedDescription }
            }
            busy = false
        }
    }
}
