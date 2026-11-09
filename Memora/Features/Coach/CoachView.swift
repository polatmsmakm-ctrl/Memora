import SwiftUI

/// AI memory coach with Socratic and explain modes. Context = the learner's own items,
/// weak areas and recent errors, so answers stay grounded in their material.
struct CoachView: View {
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter
    @State private var messages: [AIMessage] = []
    @State private var input = ""
    @State private var socratic = true
    @State private var subjectID: UUID?
    @State private var isStreaming = false
    @State private var errorText: String?
    @State private var streamTask: Task<Void, Never>?
    @State private var attachment: CoachAttachment?
    @State private var isAttaching = false
    @State private var cardSets: [UUID: GeneratedCardSet] = [:]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            weakAreasCard
                            if messages.isEmpty { suggestions }
                            ForEach(messages) { message in
                                if cardSets[message.id] != nil {
                                    FlashcardSetCard(cardSet: Binding(get: { cardSets[message.id] ?? GeneratedCardSet() },
                                                                  set: { cardSets[message.id] = $0 }))
                                        .id(message.id)
                                } else {
                                    MessageBubble(message: message).id(message.id)
                                }
                            }
                            if isStreaming && messages.last?.role == .user {
                                HStack { TypingIndicator(); Spacer() }
                            }
                            if let errorText {
                                Label(errorText, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.warning)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(Theme.padding)
                        .frame(maxWidth: 820)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
                inputBar
            }
            .memoraScreen()
            .navigationTitle(L("tab.coach"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        streamTask?.cancel()
                        messages = []
                        cardSets = [:]
                        attachment = nil
                        errorText = nil
                    } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel(L("coach.new"))
                    .disabled(messages.isEmpty)
                }
            }
            .keyboardDoneButton()
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("", selection: $socratic) {
                Text(L("coach.socratic")).tag(true)
                Text(L("coach.explain")).tag(false)
            }
            .pickerStyle(.segmented)
            .featureTip(.coachModes, isActive: router.advancedScreen == .coach)
            Picker(L("common.subject"), selection: $subjectID) {
                Text(L("common.allSubjects")).tag(UUID?.none)
                ForEach(store.db.subjects) { Text($0.name).tag(Optional($0.id)) }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal, Theme.padding)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var weakAreasCard: some View {
        let weak = store.items(in: subjectID)
            .filter { $0.isIntroduced && store.memoryState(of: $0) == .weak || $0.profile.failureCount >= 2 }
            .prefix(5)
        if !weak.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L("coach.weakAreas"), systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(Theme.warning)
                    ForEach(Array(weak)) { item in
                        Button {
                            send(LF("coach.prompt.weakItem", item.title))
                        } label: {
                            HStack {
                                Text(item.title).font(.callout).foregroundStyle(.primary)
                                Spacer()
                                if let category = item.profile.lastErrorCategory { Chip(text: category.title, tint: Theme.warning) }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!AIService.isAvailable || isStreaming)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        if AIService.isAvailable {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("coach.suggestions")).font(.subheadline.weight(.semibold))
                ForEach(["coach.s.explain", "coach.s.quiz", "coach.s.mistake", "coach.s.mnemonic", "coach.s.connections", "coach.s.prereq"], id: \.self) { key in
                    Button { send(L(key)) } label: {
                        Text(L(key)).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            EmptyStateView(systemImage: "sparkles", title: L("coach.noKey.title"), message: L("coach.noKey.message"),
                           actionTitle: L("coach.noKey.action")) { router.selectedTab = .settings }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if isAttaching {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L("coach.attach.loading")).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let attachment {
                attachmentPanel(attachment)
            }
            inputRow
        }
        .padding(.horizontal, Theme.padding)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func attachmentPanel(_ file: CoachAttachment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: file.systemImage).foregroundStyle(Theme.accent)
                Text(file.fileName).font(.footnote.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { attachment = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel(L("coach.attach.remove"))
                    .disabled(isStreaming)
            }
            if messages.isEmpty || messages.last?.role == .model {
                Text(L("coach.attach.hint")).font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        actionChip("coach.action.extract", "text.viewfinder") { send(LF("coach.msg.extract", file.fileName)) }
                        actionChip("coach.action.cards", "rectangle.on.rectangle.angled") { makeCards(words: false) }
                        actionChip("coach.action.words", "bell.badge") { makeCards(words: true) }
                        actionChip("coach.action.summary", "text.append") { send(LF("coach.msg.summary", file.fileName)) }
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func actionChip(_ key: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L(key), systemImage: icon)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.accent.opacity(0.14), in: Capsule())
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .disabled(isStreaming || !AIService.isAvailable)
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button { pickAttachment() } label: { Image(systemName: "paperclip.circle.fill").font(.system(size: 32)) }
                .foregroundStyle(Theme.accent)
                .disabled(!AIService.isAvailable || isStreaming || isAttaching)
                .accessibilityLabel(L("coach.attach"))
            TextField(L("coach.placeholder"), text: $input, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .disabled(!AIService.isAvailable)
            if isStreaming {
                Button { streamTask?.cancel() } label: { Image(systemName: "stop.circle.fill").font(.system(size: 32)) }
                    .accessibilityLabel(L("coach.stop"))
            } else {
                Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)) }
                    .disabled(TextNormalizer.isBlank(input) || !AIService.isAvailable)
                    .accessibilityLabel(L("coach.send"))
            }
        }
    }

    // MARK: Logic

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        input = ""
        errorText = nil
        messages.append(AIMessage(role: .user, text: trimmed))
        // Card sets are not plain chat text; leave them out of the conversation sent to Gemini.
        let history = messages.filter { cardSets[$0.id] == nil }
        let service = AIService.make(settings: store.settings)
        let context = learnerContext()
        let file = attachment
        isStreaming = true
        streamTask = Task {
            var reply = AIMessage(role: .model, text: "")
            var appended = false
            do {
                let stream = file.map { service.fileStream(history: history, attachment: $0) }
                    ?? service.coachStream(history: history, socratic: socratic, context: context)
                for try await chunk in stream {
                    reply.text += chunk
                    if !appended {
                        messages.append(reply)
                        appended = true
                    } else if let index = messages.lastIndex(where: { $0.id == reply.id }) {
                        messages[index].text = reply.text
                    }
                }
            } catch is CancellationError {
            } catch {
                errorText = error.localizedDescription
            }
            isStreaming = false
        }
    }

    // MARK: Files

    private func pickAttachment() {
        UIApplication.shared.dismissKeyboard()
        DocumentPicker.present { urls in
            guard let url = urls.first else { return }
            isAttaching = true
            errorText = nil
            let locale = store.settings.language.speechLocaleIdentifier
            Task {
                do {
                    attachment = try await CoachAttachment.load(from: url, speechLocale: locale)
                } catch {
                    errorText = error.localizedDescription
                }
                isAttaching = false
            }
        }
    }

    /// Asks Gemini for flashcards (or vocabulary cards) from the attached file and shows
    /// them as a card set the learner can save and get reminded about.
    private func makeCards(words: Bool) {
        guard let file = attachment, !isStreaming else { return }
        let request = LF(words ? "coach.msg.words" : "coach.msg.cards", file.fileName)
        errorText = nil
        messages.append(AIMessage(role: .user, text: request))
        let service = AIService.make(settings: store.settings)
        isStreaming = true
        streamTask = Task {
            do {
                let result = try await service.flashcards(from: file, words: words, instruction: request)
                guard !Task.isCancelled else { isStreaming = false; return }
                if result.cards.isEmpty {
                    messages.append(AIMessage(role: .model, text: L("coach.cards.empty")))
                } else {
                    let reply = AIMessage(role: .model, text: result.cards.map { "\($0.front) — \($0.back)" }.joined(separator: "\n"))
                    let title = TextNormalizer.isBlank(result.title ?? "") ? file.title : (result.title ?? file.title)
                    cardSets[reply.id] = GeneratedCardSet(title: title, cards: result.cards, type: words ? .words : .facts)
                    messages.append(reply)
                }
            } catch is CancellationError {
            } catch {
                errorText = error.localizedDescription
            }
            isStreaming = false
        }
    }

    /// Compact, grounded context: weak items with their reference answers, recent errors.
    private func learnerContext() -> String {
        let items = store.items(in: subjectID).filter(\.isIntroduced)
        let weak = items.filter { store.memoryState(of: $0) == .weak || $0.profile.failureCount >= 2 }.prefix(12)
        let recent = store.db.reviewLogs.filter { $0.errorCategory != nil }.suffix(10)
        var lines: [String] = []
        if let subject = store.subject(subjectID) { lines.append("Subject: \(subject.name)") }
        lines.append("Weak items:")
        for item in weak {
            let prereqs = store.weakPrerequisites(of: item).map(\.title).joined(separator: ", ")
            lines.append("- \(item.title): \(item.answer)" + (prereqs.isEmpty ? "" : " [weak prerequisites: \(prereqs)]"))
        }
        lines.append("Recent mistakes:")
        for log in recent {
            if let item = store.item(log.itemID), let category = log.errorCategory {
                lines.append("- \(item.title): \(category.rawValue); learner answered \"\(log.userAnswer.prefix(120))\"")
            }
        }
        lines.append("Other studied items:")
        for item in items.prefix(40) where !weak.contains(where: { $0.id == item.id }) {
            lines.append("- \(item.title): \(item.answer.prefix(200))")
        }
        return String(lines.joined(separator: "\n").prefix(8000))
    }
}

struct MessageBubble: View {
    var message: AIMessage

    /// Renders the reply's inline Markdown (bold, italics, code) safely. Using the text as a
    /// LocalizedStringKey treated "%" as a format specifier and could garble replies.
    static func render(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        let cleaned = text
            .replacingOccurrences(of: "\n### ", with: "\n")
            .replacingOccurrences(of: "\n## ", with: "\n")
            .replacingOccurrences(of: "\n# ", with: "\n")
            .replacingOccurrences(of: "\n* ", with: "\n• ")
            .replacingOccurrences(of: "\n- ", with: "\n• ")
        if let attributed = try? AttributedString(markdown: cleaned, options: options) {
            return attributed
        }
        return AttributedString(text)
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(Self.render(message.text))
                .font(.callout)
                .textSelection(.enabled)
                .padding(12)
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .background(message.role == .user ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu {
                    Button { UIPasteboard.general.string = message.text } label: { Label(L("common.copy"), systemImage: "doc.on.doc") }
                }
            if message.role == .model { Spacer(minLength: 40) }
        }
    }
}

struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().fill(Color.secondary).frame(width: 7, height: 7)
                    .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.6)))
            }
        }
        .padding(12)
        .background(Theme.surface, in: Capsule())
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi }
        }
        .accessibilityLabel(L("coach.typing"))
    }
}

// MARK: Cards made by Gemini (Add screen and coach)

struct GeneratedCardSet {
    var title = ""
    var cards: [FlashcardDTO] = []
    var type: MemorizeType = .facts
    var note: String?
    var remind = true
    var subjectID: UUID?
    var saved = false
    var savedItemIDs: [UUID] = []
    var remindStatus: String?

    var isVocabulary: Bool { type == .words }
}

struct FlashcardSetCard: View {
    @EnvironmentObject private var store: MemoraStore
    @Binding var cardSet: GeneratedCardSet
    @State private var showAll = false
    @State private var saving = false

    private let previewCount = 8

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: cardSet.type.icon).foregroundStyle(Theme.accent)
                    Text(cardSet.title).font(.headline).lineLimit(2)
                    Spacer()
                    Chip(text: LF(cardSet.isVocabulary ? "coach.words.title" : "coach.cards.title", cardSet.cards.count))
                }
                if let note = cardSet.note {
                    Label(note, systemImage: "lightbulb").font(.footnote).foregroundStyle(.secondary)
                }
                let shown = showAll ? cardSet.cards : Array(cardSet.cards.prefix(previewCount))
                ForEach(Array(shown.enumerated()), id: \.offset) { offset, card in
                    let previousSection = offset > 0 ? shown[offset - 1].section : nil
                    if let section = card.section, section != previousSection {
                        Text(section).font(.caption.weight(.bold)).foregroundStyle(Theme.accent).padding(.top, 4)
                    }
                    cardRow(card)
                }
                if cardSet.cards.count > previewCount && !showAll {
                    Button(LF("coach.cards.more", cardSet.cards.count - previewCount)) { showAll = true }.font(.footnote)
                }
                Divider()
                if cardSet.saved {
                    Label(L("coach.cards.saved"), systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(Theme.success)
                    if let status = cardSet.remindStatus { Text(status).font(.footnote).foregroundStyle(.secondary) }
                } else {
                    HStack {
                        Text(L("coach.cards.subject")).font(.footnote)
                        Spacer()
                        Picker(L("coach.cards.subject"), selection: $cardSet.subjectID) {
                            Text(cardSet.title).tag(UUID?.none)
                            ForEach(store.db.subjects) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .pickerStyle(.menu)
                    }
                    Toggle(L("coach.cards.remind"), isOn: $cardSet.remind).font(.footnote)
                    Button { save() } label: {
                        if saving { ProgressView() } else { Label(L("coach.cards.save"), systemImage: "tray.and.arrow.down") }
                    }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(saving)
                }
            }
        }
    }

    private func cardRow(_ card: FlashcardDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if card.isApplication == true {
                Text(L("memo.application")).font(.caption2.weight(.bold)).foregroundStyle(Theme.violet)
            }
            Text(card.front).font(.callout.weight(.semibold))
            Text(card.back).font(.callout).foregroundStyle(.secondary)
            if let example = card.example { Text(example).font(.caption).italic().foregroundStyle(.secondary) }
            if let mnemonic = card.mnemonic {
                Label(mnemonic, systemImage: "sparkles").font(.caption).foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            Button { UIPasteboard.general.string = card.front + " — " + card.back } label: { Label(L("common.copy"), systemImage: "doc.on.doc") }
        }
    }

    private func save() {
        saving = true
        let subjectID: UUID
        if let id = cardSet.subjectID, store.subject(id) != nil {
            subjectID = id
        } else {
            let subject = Subject(name: cardSet.title.trimmingCharacters(in: .whitespacesAndNewlines))
            store.addSubject(subject)
            subjectID = subject.id
        }
        let now = Date()
        let type = cardSet.type
        let setTitle = cardSet.title
        let remind = cardSet.remind
        let items: [LearningItem] = cardSet.cards.enumerated().map { offset, card in
            var item = LearningItem(subjectID: subjectID,
                                    kind: type.itemKind,
                                    title: type == .poem ? "\(setTitle) — \(offset + 1)" : String(card.front.prefix(80)),
                                    prompt: card.front,
                                    answer: card.back,
                                    explanation: card.explanation ?? "",
                                    examples: card.example.map { [$0] } ?? [],
                                    hints: card.hint.map { [$0] } ?? [],
                                    mnemonics: card.mnemonic.map { [Mnemonic(kind: type == .words ? .keyword : .association,
                                                                             content: $0, explanation: "", origin: .ai)] } ?? [],
                                    tags: [setTitle, card.section].compactMap { $0 },
                                    origin: .ai,
                                    createdAt: now.addingTimeInterval(Double(offset) * 0.001))
            if remind {
                // Start the spacing schedule now: the first recall prompts arrive in small
                // batches (5 cards every 2 hours) instead of all at once.
                item.introducedAt = now
                item.card.due = now.addingTimeInterval(15 * 60 + Double(offset / 5) * 2 * 3600)
            }
            return item
        }
        store.addItems(items)
        cardSet.savedItemIDs = items.map(\.id)
        Task {
            if remind {
                let service = ReminderService.shared
                await service.refreshAuthorization()
                if service.authorization == .notDetermined { await service.requestAuthorization() }
                if !store.settings.reminders.enabled { store.settings.reminders.enabled = true }
                await service.refresh(store: store)
                let allowed = [.authorized, .provisional, .ephemeral].contains(service.authorization)
                cardSet.remindStatus = allowed ? L("memo.remindOn") : L("coach.cards.remindDenied")
            }
            cardSet.saved = true
            saving = false
            Haptics.success()
        }
    }
}
