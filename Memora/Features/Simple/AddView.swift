import SwiftUI
import PhotosUI

/// The one place to add material: a file, a photo, a scanned page or typed text goes to
/// Gemini, which returns word cards or question cards to save (with optional reminders).
struct AddView: View {
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter

    @State private var words = true
    @State private var textMode = false
    @State private var text = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showScanner = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var result: GeneratedCardSet?
    @State private var work: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !AIService.isAvailable {
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
                    run(name: L("add.scan.name")) { try CoachAttachment.fromImages(images, name: L("add.scan.name")) }
                }, onCancel: { showScanner = false })
                .ignoresSafeArea()
            }
        }
    }

    // MARK: Sections

    private var inputSection: some View {
        VStack(spacing: 14) {
            Text(L("add.intro"))
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text(L("add.kind")).font(.subheadline.weight(.semibold))
                Picker(L("add.kind"), selection: $words) {
                    Text(L("add.kind.words")).tag(true)
                    Text(L("add.kind.cards")).tag(false)
                }
                .pickerStyle(.segmented)
            }

            if textMode {
                GlassCard {
                    VStack(spacing: 10) {
                        AnswerEditor(text: $text, placeholder: L("add.text.placeholder"), minHeight: 200)
                        HStack {
                            Button(L("common.cancel")) { textMode = false }
                                .buttonStyle(SecondaryButtonStyle(tint: .secondary))
                            Spacer()
                            Button(L("add.text.go")) { useText() }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(TextNormalizer.isBlank(text))
                        }
                    }
                }
            } else {
                bigButton(L("add.file"), L("add.file.sub"), "doc.richtext") { pickFile() }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    bigLabel(L("add.photo"), nil, "photo.on.rectangle")
                }
                .buttonStyle(.plain)
                if DocumentScannerView.isSupported {
                    bigButton(L("add.scan"), nil, "doc.viewfinder") { showScanner = true }
                }
                bigButton(L("add.text"), nil, "text.alignleft") { textMode = true }
            }
        }
    }

    private var busyCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(L("add.busy")).font(.callout).multilineTextAlignment(.center)
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
            if !result.savedItemIDs.isEmpty {
                Button {
                    router.start(SessionRequest(mode: .learn, itemIDs: Array(result.savedItemIDs.prefix(20))))
                } label: { Label(L("add.startNow"), systemImage: "play.fill") }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            }
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
            Button(L("add.manual")) { router.openImport() }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: .secondary))
        }
    }

    private func bigButton(_ title: String, _ subtitle: String?, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { bigLabel(title, subtitle, icon) }.buttonStyle(.plain)
    }

    private func bigLabel(_ title: String, _ subtitle: String?, _ icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .contentShape(Rectangle())
    }

    // MARK: Actions

    private func reset() {
        work?.cancel()
        result = nil
        text = ""
        textMode = false
        errorText = nil
        busy = false
    }

    private func pickFile() {
        UIApplication.shared.dismissKeyboard()
        let locale = store.settings.language.speechLocaleIdentifier
        DocumentPicker.present { urls in
            guard let url = urls.first else { return }
            run(name: url.deletingPathExtension().lastPathComponent) {
                try await CoachAttachment.load(from: url, speechLocale: locale)
            }
        }
    }

    private func useText() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIApplication.shared.dismissKeyboard()
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? L("add.text.name")
        let name = String(firstLine.prefix(40))
        run(name: name) { CoachAttachment(fileName: name, systemImage: "text.alignleft", extractedText: trimmed) }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        run(name: L("add.photo.name")) {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                throw ImportError.unreadable
            }
            return try CoachAttachment.fromImages([image], name: L("add.photo.name"))
        }
    }

    /// Prepares the attachment, asks Gemini for cards and shows the result to save.
    private func run(name: String, _ prepare: @escaping () async throws -> CoachAttachment) {
        work?.cancel()
        errorText = nil
        busy = true
        let wantsWords = words
        let service = AIService.make(settings: store.settings)
        work = Task {
            do {
                let attachment = try await prepare()
                let instruction = LF(wantsWords ? "coach.msg.words" : "coach.msg.cards", attachment.fileName)
                let set = try await service.flashcards(from: attachment, words: wantsWords, instruction: instruction)
                guard !Task.isCancelled else { return }
                if set.cards.isEmpty {
                    errorText = L("coach.cards.empty")
                } else {
                    let title = TextNormalizer.isBlank(set.title ?? "") ? name : (set.title ?? name)
                    result = GeneratedCardSet(title: title, cards: set.cards, isVocabulary: wantsWords, remind: wantsWords)
                    textMode = false
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
