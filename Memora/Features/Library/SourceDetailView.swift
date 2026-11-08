import SwiftUI

struct SourcesListView: View {
    @EnvironmentObject private var store: MemoraStore
    @State private var search = ""

    private var sources: [SourceDocument] {
        let query = TextNormalizer.normalize(search)
        return store.db.sources
            .filter { query.isEmpty || TextNormalizer.normalize($0.title).contains(query) }
            .sorted { $0.importedAt > $1.importedAt }
    }

    var body: some View {
        List {
            if sources.isEmpty {
                Text(L("sources.empty")).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(sources) { source in
                NavigationLink { SourceDetailView(sourceID: source.id, highlight: nil) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: source.kind.systemImage).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title).font(.callout.weight(.medium)).lineLimit(1)
                            Text((store.subject(source.subjectID)?.name ?? "") + " · " + Formatters.date(source.importedAt))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { sources[$0].id }
                for id in ids { store.deleteSource(id) }
            }
            .listRowBackground(Theme.surface)
        }
        .memoraScreen()
        .navigationTitle(L("library.sources"))
        .searchable(text: $search)
    }
}

/// Original imported text, verbatim, for verification of every learning unit.
struct SourceDetailView: View {
    let sourceID: UUID
    var highlight: String?
    @EnvironmentObject private var store: MemoraStore

    var body: some View {
        ScrollView {
            if let source = store.source(sourceID) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Chip(text: source.kind.title, systemImage: source.kind.systemImage)
                        if let file = source.originalFileName { Text(file).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Text(L("sources.verbatim")).font(.caption).foregroundStyle(.secondary)
                    ForEach(source.sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            if let heading = section.heading {
                                Text(heading).font(section.level <= 1 ? .title3.weight(.semibold) : .headline)
                            }
                            if let page = section.pageNumber {
                                Text(LF("item.page", page)).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text(section.text)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(isHighlighted(section) ? 8 : 0)
                                .background(isHighlighted(section) ? Theme.accentSoft : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    let items = store.db.items.filter { $0.sourceReference?.sourceID == sourceID }
                    if !items.isEmpty {
                        Divider()
                        Text(LF("sources.units", items.count)).font(.headline)
                        ForEach(items) { item in
                            NavigationLink { ItemDetailView(itemID: item.id) } label: { ItemRow(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Theme.padding)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .memoraScreen()
        .navigationTitle(store.source(sourceID)?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isHighlighted(_ section: SourceSection) -> Bool {
        guard let highlight, !highlight.isEmpty else { return false }
        return AIResponseValidator.quoteFound(highlight, in: section.text)
    }
}
