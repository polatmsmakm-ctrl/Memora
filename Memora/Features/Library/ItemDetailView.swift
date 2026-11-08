import SwiftUI
import Charts

struct ItemDetailView: View {
    let itemID: UUID
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var editing: LearningItem?
    @State private var showLinkSheet = false
    @State private var showMnemonicSheet = false
    @State private var aiBusy = false
    @State private var aiMessage: String?
    @State private var confirmDelete = false
    @State private var confirmReset = false

    private var item: LearningItem? { store.item(itemID) }

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                EmptyStateView(systemImage: "questionmark.folder", title: L("item.missing"), message: "")
            }
        }
        .memoraScreen()
        .navigationTitle(item?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ item: LearningItem) -> some View {
        List {
            Section { overview(item) }.listRowBackground(Color.clear)
            Section(L("item.memoryProfile")) { profile(item) }.listRowBackground(Theme.surface)
            if item.profile.confidenceHistory.count >= 2 {
                Section(L("item.confidenceHistory")) { confidenceChart(item) }.listRowBackground(Theme.surface)
            }
            Section(L("item.mnemonics")) { mnemonics(item) }.listRowBackground(Theme.surface)
            Section(L("item.deeper")) { deeper(item) }.listRowBackground(Theme.surface)
            Section(L("item.links")) { linksSection(item) }.listRowBackground(Theme.surface)
            if let reference = item.sourceReference { Section(L("item.source")) { sourceSection(reference) }.listRowBackground(Theme.surface) }
            Section(L("item.history")) { history(item) }.listRowBackground(Theme.surface)
            Section { actions(item) }.listRowBackground(Theme.surface)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L("common.edit")) { editing = item }
            }
        }
        .sheet(item: $editing) { draft in
            ItemEditorView(item: draft, isNew: false).environmentObject(store)
        }
        .sheet(isPresented: $showLinkSheet) {
            LinkEditorSheet(item: item).environmentObject(store)
        }
        .sheet(isPresented: $showMnemonicSheet) {
            MnemonicEditorSheet(itemID: item.id).environmentObject(store)
        }
        .confirmationDialog(L("item.delete.title"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("common.delete"), role: .destructive) { store.deleteItem(item.id); dismiss() }
        }
        .confirmationDialog(L("item.reset.title"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("item.reset"), role: .destructive) {
                var copy = item
                copy.resetProgress()
                store.upsertItem(copy)
            }
        } message: {
            Text(L("item.reset.message"))
        }
    }

    // MARK: Sections

    private func overview(_ item: LearningItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                MemoryStateBadge(state: store.memoryState(of: item))
                Chip(text: item.kind.title, tint: .secondary)
                OriginBadge(origin: item.origin)
                if item.isSuspended { Chip(text: L("item.suspended"), systemImage: "pause", tint: Theme.warning) }
            }
            if let image = ImageStore.load(item.imageFileName) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text(item.prompt).font(.headline)
            Text(item.answer).font(.body).textSelection(.enabled)
            if !item.keyPoints.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(item.keyPoints, id: \.self) { Chip(text: $0, tint: Theme.violet) }
                }
            }
            if !item.explanation.isEmpty {
                Text(item.explanation).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func profile(_ item: LearningItem) -> some View {
        let r = store.retrievability(of: item)
        let mastered = MemoryStateClassifier.isMastered(item)
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(title: L("item.retrievability"), value: item.isIntroduced ? Formatters.percent(r) : "—",
                         systemImage: "function", tint: Theme.violet, footnote: L("item.predictedNote"))
                StatTile(title: L("item.stability"), value: item.isIntroduced ? LF("unit.daysShort", Formatters.number(item.card.stability)) : "—",
                         systemImage: "anchor")
                StatTile(title: L("item.difficulty"), value: item.isIntroduced ? Formatters.number(item.card.difficulty) + " / 10" : "—",
                         systemImage: "dial.medium")
                StatTile(title: L("item.nextReview"), value: item.isIntroduced ? Formatters.relative(item.card.due) : "—",
                         systemImage: "calendar")
            }
            row(L("item.desiredRetention"), Formatters.percent(store.settings.fsrs.desiredRetention))
            row(L("item.created"), Formatters.date(item.createdAt))
            row(L("item.firstLearned"), item.introducedAt.map { Formatters.date($0) } ?? "—")
            row(L("item.lastReview"), item.card.lastReview.map { Formatters.date($0, time: .short) } ?? "—")
            row(L("item.counts"), LF("item.countsValue", item.profile.successCount, item.profile.partialCount, item.profile.failureCount))
            row(L("item.lapses"), "\(item.card.lapses)")
            row(L("item.sessions"), "\(item.profile.sessionIDs.count)")
            row(L("item.delayed"), "\(item.profile.delayedRecallSuccesses)")
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("item.successiveRelearning")).font(.callout)
                    Spacer()
                    Text("\(min(item.profile.distinctSuccessfulDays, MemoryStateClassifier.masterySessions))/\(MemoryStateClassifier.masterySessions)")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                ProgressBar(value: MemoryStateClassifier.relearningProgress(item), tint: Theme.success)
            }
            Text(mastered ? L("item.mastery.yes") : L("item.mastery.no")).font(.caption).foregroundStyle(.secondary)
            if let revoked = item.profile.masteryRevokedAt {
                Text(LF("item.mastery.revoked", Formatters.date(revoked))).font(.caption).foregroundStyle(Theme.warning)
            }
            let errors = ErrorCategory.allCases.filter { item.profile.errorCount($0) > 0 }
            if !errors.isEmpty {
                Text(L("item.errors")).font(.subheadline.weight(.semibold))
                ForEach(errors) { category in
                    HStack {
                        Label(category.title, systemImage: category.systemImage).font(.caption)
                        Spacer()
                        Text("\(item.profile.errorCount(category))").font(.caption.monospacedDigit())
                    }
                }
            }
            Text(L("item.buckets")).font(.subheadline.weight(.semibold))
            ForEach(KnowledgeBucket.allCases) { bucket in
                let tally = item.profile.tally(bucket)
                HStack {
                    Text(bucket.title).font(.caption)
                    Spacer()
                    Text(tally.attempts == 0 ? "—" : "\(tally.successes)/\(tally.attempts)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Text(value).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private func confidenceChart(_ item: LearningItem) -> some View {
        Chart(Array(item.profile.confidenceHistory.enumerated()), id: \.offset) { entry in
            PointMark(x: .value("#", entry.offset + 1), y: .value(L("item.confidence"), entry.element.confidence.probability))
                .foregroundStyle(entry.element.wasCorrect ? Theme.success : Theme.danger)
                .symbolSize(60)
        }
        .chartYScale(domain: 0...1)
        .chartYAxis { AxisMarks(values: [0.25, 0.5, 0.75, 1]) }
        .frame(height: 140)
        .accessibilityLabel(L("item.confidenceHistory"))
    }

    @ViewBuilder
    private func mnemonics(_ item: LearningItem) -> some View {
        ForEach(item.mnemonics) { m in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(m.kind.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.violet)
                    OriginBadge(origin: m.origin)
                }
                Text(m.content).font(.callout)
                if !m.explanation.isEmpty { Text(m.explanation).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .onDelete { offsets in
            var copy = item
            copy.mnemonics.remove(atOffsets: offsets)
            store.upsertItem(copy)
        }
        Menu {
            Button { addAutomaticMnemonics(item) } label: { Label(L("item.mnemonic.auto"), systemImage: "wand.and.stars") }
            if AIService.isAvailable {
                ForEach(MnemonicKind.allCases) { kind in
                    Button { generateMnemonic(item, kind: kind) } label: { Label(kind.title, systemImage: "sparkles") }
                }
            }
            Button { showMnemonicSheet = true } label: { Label(L("item.mnemonic.manual"), systemImage: "square.and.pencil") }
        } label: {
            Label(aiBusy ? L("common.working") : L("item.mnemonic.add"), systemImage: "plus.circle")
        }
        .disabled(aiBusy)
        if let aiMessage { Text(aiMessage).font(.caption).foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private func deeper(_ item: LearningItem) -> some View {
        if item.elaborations.isEmpty && item.examples.isEmpty && item.transferProblems.isEmpty && item.promptVariants.isEmpty {
            Text(L("item.deeper.empty")).font(.footnote).foregroundStyle(.secondary)
        }
        ForEach(item.elaborations) { q in
            VStack(alignment: .leading, spacing: 3) {
                HStack { Chip(text: q.kind.title); OriginBadge(origin: q.origin) }
                Text(q.question).font(.callout.weight(.medium))
                Text(q.answer).font(.caption).foregroundStyle(.secondary)
            }
        }
        if !item.examples.isEmpty { BulletList(title: L("item.examples"), items: item.examples, systemImage: "list.bullet.rectangle", tint: Theme.accent) }
        if !item.analogies.isEmpty { BulletList(title: L("item.analogies"), items: item.analogies, systemImage: "arrow.left.arrow.right", tint: Theme.violet) }
        ForEach(item.transferProblems) { p in
            VStack(alignment: .leading, spacing: 3) {
                HStack { Chip(text: p.level.title, systemImage: "arrow.triangle.branch"); OriginBadge(origin: p.origin) }
                Text(p.problem).font(.callout)
            }
        }
        if !item.promptVariants.isEmpty {
            BulletList(title: L("item.variants"), items: item.promptVariants.map(\.prompt), systemImage: "text.redaction", tint: Theme.accent)
        }
        if AIService.isAvailable {
            Button {
                enrich(item)
            } label: {
                Label(aiBusy ? L("common.working") : L("item.enrich"), systemImage: "sparkles")
            }
            .disabled(aiBusy)
        } else {
            Text(L("item.enrich.noAI")).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func linksSection(_ item: LearningItem) -> some View {
        let links = store.links(for: item.id)
        if links.isEmpty { Text(L("item.links.empty")).font(.footnote).foregroundStyle(.secondary) }
        ForEach(links) { link in
            let otherID = link.fromID == item.id ? link.toID : link.fromID
            if let other = store.item(otherID) {
                NavigationLink { ItemDetailView(itemID: other.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(linkDescription(link, current: item.id)).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text(other.title).font(.callout)
                            Spacer()
                            MemoryStateBadge(state: store.memoryState(of: other))
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { store.removeLink(link.id) } label: { Label(L("common.delete"), systemImage: "trash") }
                }
            }
        }
        Button { showLinkSheet = true } label: { Label(L("item.links.add"), systemImage: "link.badge.plus") }
    }

    private func linkDescription(_ link: ConceptLink, current: UUID) -> String {
        if link.kind == .prerequisite {
            return link.toID == current ? L("item.links.requires") : L("item.links.requiredBy")
        }
        return link.kind.title
    }

    @ViewBuilder
    private func sourceSection(_ reference: SourceReference) -> some View {
        Text("“" + reference.quote + "”").font(.callout).italic()
        if let source = store.source(reference.sourceID) {
            NavigationLink { SourceDetailView(sourceID: source.id, highlight: reference.quote) } label: {
                Label(source.title + (reference.pageNumber.map { " · " + LF("item.page", $0) } ?? ""), systemImage: source.kind.systemImage)
            }
        }
    }

    @ViewBuilder
    private func history(_ item: LearningItem) -> some View {
        let logs = store.logs(for: item.id)
        if logs.isEmpty { Text(L("item.history.empty")).font(.footnote).foregroundStyle(.secondary) }
        ForEach(logs.prefix(30)) { log in
            HStack(alignment: .top) {
                Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(Theme.color(for: log.outcome)).padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.exerciseType.title + " · " + log.mode.title).font(.caption.weight(.medium))
                    Text(Formatters.date(log.date, time: .short)).font(.caption2).foregroundStyle(.secondary)
                    if let category = log.errorCategory { Text(category.title).font(.caption2).foregroundStyle(Theme.warning) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(log.outcome.title).font(.caption)
                    if log.countedForScheduling {
                        Text(LF("item.history.predicted", Formatters.percent(log.retrievabilityBefore))).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ item: LearningItem) -> some View {
        Button {
            router.start(SessionRequest(mode: item.isIntroduced ? .remember : .learn, itemIDs: [item.id]))
        } label: { Label(L("item.practice"), systemImage: "play.circle") }
        Button {
            var copy = item
            copy.isSuspended.toggle()
            store.upsertItem(copy)
        } label: {
            Label(item.isSuspended ? L("item.resume") : L("item.suspend"), systemImage: item.isSuspended ? "play" : "pause")
        }
        Button(role: .destructive) { confirmReset = true } label: { Label(L("item.reset"), systemImage: "arrow.counterclockwise") }
        Button(role: .destructive) { confirmDelete = true } label: { Label(L("common.delete"), systemImage: "trash") }
    }

    // MARK: AI & mnemonics

    private func addAutomaticMnemonics(_ item: LearningItem) {
        let generated = MnemonicGenerator.automatic(for: item)
        guard !generated.isEmpty else {
            aiMessage = L("item.mnemonic.autoNone")
            return
        }
        var copy = item
        copy.mnemonics.append(contentsOf: generated)
        store.upsertItem(copy)
        Haptics.success()
    }

    private func generateMnemonic(_ item: LearningItem, kind: MnemonicKind) {
        aiBusy = true
        aiMessage = nil
        let service = AIService.make(settings: store.settings)
        Task {
            do {
                let mnemonic = try await service.mnemonic(for: item, kind: kind)
                if var latest = store.item(item.id) {
                    latest.mnemonics.append(mnemonic)
                    store.upsertItem(latest)
                }
                Haptics.success()
            } catch {
                aiMessage = error.localizedDescription
            }
            aiBusy = false
        }
    }

    private func enrich(_ item: LearningItem) {
        aiBusy = true
        aiMessage = nil
        let service = AIService.make(settings: store.settings)
        let sourceText = item.sourceReference.flatMap { store.source($0.sourceID)?.text }
        Task {
            do {
                let enrichment = try await service.enrich(item: item, sourceText: sourceText)
                if var latest = store.item(item.id) {
                    latest.elaborations.append(contentsOf: enrichment.elaborations)
                    latest.examples.append(contentsOf: enrichment.examples.filter { !latest.examples.contains($0) })
                    latest.analogies.append(contentsOf: enrichment.analogies.filter { !latest.analogies.contains($0) })
                    latest.transferProblems.append(contentsOf: enrichment.transferProblems)
                    latest.promptVariants.append(contentsOf: enrichment.promptVariants)
                    latest.hints.append(contentsOf: enrichment.hints)
                    store.upsertItem(latest)
                }
                aiMessage = enrichment.rejectedCount > 0 ? LF("item.enrich.rejected", enrichment.rejectedCount) : L("item.enrich.done")
                Haptics.success()
            } catch {
                aiMessage = error.localizedDescription
            }
            aiBusy = false
        }
    }
}

struct LinkEditorSheet: View {
    let item: LearningItem
    @EnvironmentObject private var store: MemoraStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind: LinkKind = .related
    @State private var direction = 0
    @State private var search = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(L("link.kind"), selection: $kind) {
                        ForEach(LinkKind.allCases) { Text($0.title).tag($0) }
                    }
                    if kind == .prerequisite {
                        Picker(L("link.direction"), selection: $direction) {
                            Text(L("link.direction.requires")).tag(0)
                            Text(L("link.direction.requiredBy")).tag(1)
                        }
                        .pickerStyle(.segmented)
                    }
                    if let message { Text(message).font(.caption).foregroundStyle(Theme.warning) }
                }
                Section(L("link.target")) {
                    ForEach(candidates) { other in
                        Button {
                            let from = kind == .prerequisite && direction == 0 ? other.id : item.id
                            let to = from == item.id ? other.id : item.id
                            if store.addLink(from: from, to: to, kind: kind) {
                                Haptics.success()
                                dismiss()
                            } else {
                                message = L("link.rejected")
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(other.title).foregroundStyle(.primary)
                                Text(store.subject(other.subjectID)?.name ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .memoraScreen()
            .searchable(text: $search)
            .navigationTitle(L("item.links.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } } }
        }
    }

    private var candidates: [LearningItem] {
        let query = TextNormalizer.normalize(search)
        return store.db.items.filter { $0.id != item.id && (query.isEmpty || TextNormalizer.normalize($0.title).contains(query)) }
            .sorted { ($0.subjectID == item.subjectID ? 0 : 1, $0.title) < ($1.subjectID == item.subjectID ? 0 : 1, $1.title) }
    }
}

struct MnemonicEditorSheet: View {
    let itemID: UUID
    @EnvironmentObject private var store: MemoraStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind: MnemonicKind = .imagery
    @State private var content = ""
    @State private var explanation = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker(L("mnemonic.kind"), selection: $kind) {
                    ForEach(MnemonicKind.allCases) { Text($0.title).tag($0) }
                }
                Section(L("mnemonic.content")) {
                    TextField(L("mnemonic.content.placeholder"), text: $content, axis: .vertical).lineLimit(3...8)
                }
                Section(L("mnemonic.explanation")) {
                    TextField(L("mnemonic.explanation.placeholder"), text: $explanation, axis: .vertical).lineLimit(2...6)
                }
            }
            .memoraScreen()
            .navigationTitle(L("item.mnemonic.manual"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.save")) {
                        if var item = store.item(itemID) {
                            item.mnemonics.append(Mnemonic(kind: kind, content: content, explanation: explanation, origin: .user))
                            store.upsertItem(item)
                        }
                        dismiss()
                    }
                    .disabled(TextNormalizer.isBlank(content))
                }
            }
            .keyboardDoneButton()
        }
    }
}
