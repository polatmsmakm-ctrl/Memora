import SwiftUI

/// Prior-knowledge map: the learner marks each concept as known / partly known / new
/// before studying. Known items skip the explanation and go straight to a retrieval
/// check; prerequisites are listed so foundational gaps are visible first.
struct PriorKnowledgeView: View {
    let subjectID: UUID
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter

    private var items: [LearningItem] {
        let builder = SessionBuilder(scheduler: store.scheduler, settings: store.settings, now: Date())
        let pool = store.items(in: subjectID).filter { $0.card.state == .new && !$0.isSuspended }
        return builder.orderedNewItems(pool: pool, links: store.db.links, limit: pool.count)
    }

    var body: some View {
        List {
            Section {
                Text(L("prior.explain")).font(.footnote).foregroundStyle(.secondary)
                    .featureTip(.priorKnowledge)
                summaryRow
            }
            ForEach(items) { item in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title).font(.headline)
                        Text(item.prompt).font(.caption).foregroundStyle(.secondary)
                        let prerequisites = PrerequisiteAnalyzer.prerequisiteIDs(of: item.id, links: store.db.links).compactMap { store.item($0) }
                        if !prerequisites.isEmpty {
                            Text(LF("prior.requires", prerequisites.map(\.title).joined(separator: "، ")))
                                .font(.caption2).foregroundStyle(Theme.warning)
                        }
                        Picker(L("prior.title"), selection: Binding(get: { item.priorKnowledge },
                                                                    set: { store.setPriorKnowledge($0, for: item.id) })) {
                            ForEach([PriorKnowledge.known, .partial, .new]) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.surface)
            }
            Section {
                Button {
                    router.start(SessionRequest(mode: .learn, subjectID: subjectID))
                } label: {
                    Label(L("learn.hub.start"), systemImage: "book")
                }
                .disabled(items.isEmpty)
            }
        }
        .memoraScreen()
        .navigationTitle(L("prior.title"))
    }

    private var summaryRow: some View {
        let all = items
        let known = all.filter { $0.priorKnowledge == .known }.count
        let partial = all.filter { $0.priorKnowledge == .partial }.count
        let new = all.filter { $0.priorKnowledge == .new }.count
        let unmapped = all.count - known - partial - new
        return HStack {
            Chip(text: "\(PriorKnowledge.known.title) \(known)", tint: Theme.success)
            Chip(text: "\(PriorKnowledge.partial.title) \(partial)", tint: Theme.warning)
            Chip(text: "\(PriorKnowledge.new.title) \(new)", tint: Theme.violet)
            if unmapped > 0 { Chip(text: "? \(unmapped)", tint: .secondary) }
        }
    }
}
