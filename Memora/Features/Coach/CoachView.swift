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
                                MessageBubble(message: message).id(message.id)
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
        HStack(alignment: .bottom, spacing: 8) {
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
        .padding(.horizontal, Theme.padding)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: Logic

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        input = ""
        errorText = nil
        messages.append(AIMessage(role: .user, text: trimmed))
        let history = messages
        let service = AIService.make(settings: store.settings)
        let context = learnerContext()
        isStreaming = true
        streamTask = Task {
            var reply = AIMessage(role: .model, text: "")
            var appended = false
            do {
                for try await chunk in service.coachStream(history: history, socratic: socratic, context: context) {
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

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(LocalizedStringKey(message.text))
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
