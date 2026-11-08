import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter
    @State private var search = ""
    @State private var showNewSubject = false

    var body: some View {
        NavigationStack {
            List {
                if store.db.subjects.isEmpty {
                    Section {
                        EmptyStateView(systemImage: "books.vertical", title: L("library.empty.title"), message: L("library.empty.message"),
                                       actionTitle: L("library.import")) { router.openImport() }
                    }
                    .listRowBackground(Color.clear)
                }
                if !search.isEmpty {
                    Section(L("library.searchResults")) {
                        ForEach(searchResults) { item in
                            NavigationLink { ItemDetailView(itemID: item.id) } label: { ItemRow(item: item) }
                        }
                    }
                    .listRowBackground(Theme.surface)
                } else {
                    Section(L("library.subjects")) {
                        ForEach(store.db.subjects) { subject in
                            NavigationLink { SubjectDetailView(subjectID: subject.id) } label: { SubjectRow(subject: subject) }
                        }
                    }
                    .listRowBackground(Theme.surface)

                    Section(L("library.tools")) {
                        NavigationLink { KnowledgeGraphView(subjectID: nil) } label: {
                            Label(L("graph.title"), systemImage: "point.3.connected.trianglepath.dotted")
                        }
                        NavigationLink { MemoryPalaceListView() } label: {
                            Label(L("palace.title"), systemImage: "building.columns")
                        }
                        NavigationLink { SourcesListView() } label: {
                            Label(L("library.sources"), systemImage: "doc.on.doc")
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .memoraScreen()
            .navigationTitle(L("tab.library"))
            .searchable(text: $search, prompt: L("library.search"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { router.openImport() } label: { Label(L("library.import"), systemImage: "square.and.arrow.down") }
                        Button { showNewSubject = true } label: { Label(L("library.newSubject"), systemImage: "folder.badge.plus") }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L("library.add"))
                }
            }
            .sheet(isPresented: $showNewSubject) {
                SubjectEditor(subject: Subject(name: ""))
                    .environmentObject(store)
            }
        }
    }

    private var searchResults: [LearningItem] {
        let query = TextNormalizer.normalize(search)
        guard !query.isEmpty else { return [] }
        return store.db.items.filter {
            TextNormalizer.normalize($0.title + " " + $0.prompt + " " + $0.answer + " " + $0.tags.joined(separator: " ")).contains(query)
        }
    }
}

struct SubjectRow: View {
    var subject: Subject
    @EnvironmentObject private var store: MemoraStore

    var body: some View {
        let items = store.items(in: subject.id)
        let learned = items.filter(\.isIntroduced).count
        HStack(spacing: 12) {
            Image(systemName: subject.symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name).font(.headline)
                Text(LF("library.subjectStats", items.count, learned)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ItemRow: View {
    var item: LearningItem
    @EnvironmentObject private var store: MemoraStore

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(item.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            MemoryStateBadge(state: store.memoryState(of: item))
        }
        .padding(.vertical, 2)
    }
}

struct SubjectEditor: View {
    @State var subject: Subject
    @EnvironmentObject private var store: MemoraStore
    @Environment(\.dismiss) private var dismiss

    private let symbols = ["book.closed", "brain", "atom", "function", "globe.europe.africa", "cross.case", "leaf", "building.columns",
                           "chart.bar", "music.note", "paintpalette", "laptopcomputer", "character.book.closed", "scalemass", "flask"]

    var body: some View {
        NavigationStack {
            Form {
                Section(L("subject.name")) {
                    TextField(L("subject.name.placeholder"), text: $subject.name)
                    TextField(L("subject.details"), text: $subject.details, axis: .vertical)
                }
                Section(L("subject.icon")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
                        ForEach(symbols, id: \.self) { symbol in
                            Button {
                                subject.symbol = symbol
                                Haptics.selection()
                            } label: {
                                Image(systemName: symbol)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(subject.symbol == symbol ? Color.white : Theme.accent)
                                    .background(subject.symbol == symbol ? Theme.accent : Theme.accentSoft,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .memoraScreen()
            .navigationTitle(subject.name.isEmpty ? L("library.newSubject") : subject.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.save")) {
                        subject.name = subject.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if store.subject(subject.id) == nil { store.addSubject(subject) } else { store.updateSubject(subject) }
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(TextNormalizer.isBlank(subject.name))
                }
            }
            .keyboardDoneButton()
        }
    }
}
