import SwiftUI

struct SubjectDetailView: View {
    let subjectID: UUID
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var stateFilter: MemoryState?
    @State private var newItem: LearningItem?
    @State private var editSubject: Subject?
    @State private var confirmDelete = false

    private var subject: Subject? { store.subject(subjectID) }

    private var items: [LearningItem] {
        let query = TextNormalizer.normalize(search)
        return store.items(in: subjectID).filter { item in
            (stateFilter == nil || store.memoryState(of: item) == stateFilter)
                && (query.isEmpty || TextNormalizer.normalize(item.title + " " + item.prompt + " " + item.answer).contains(query))
        }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(nil, title: L("common.all"))
                        ForEach(MemoryState.allCases) { state in filterChip(state, title: state.title) }
                    }
                }
            }
            .listRowBackground(Color.clear)

            Section(LF("subject.itemsCount", items.count)) {
                if items.isEmpty {
                    Text(L("subject.noItems")).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    NavigationLink { ItemDetailView(itemID: item.id) } label: { ItemRow(item: item) }
                }
                .onDelete { offsets in
                    let targets = offsets.map { items[$0].id }
                    for id in targets { store.deleteItem(id) }
                }
            }
            .listRowBackground(Theme.surface)
        }
        .memoraScreen()
        .navigationTitle(subject?.name ?? "")
        .searchable(text: $search, prompt: L("library.search"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { newItem = LearningItem(subjectID: subjectID, title: "", prompt: "", answer: "") } label: {
                        Label(L("subject.addItem"), systemImage: "square.and.pencil")
                    }
                    Button { router.openImport(subjectID: subjectID) } label: {
                        Label(L("library.import"), systemImage: "square.and.arrow.down")
                    }
                    Button { editSubject = subject } label: { Label(L("common.edit"), systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label(L("common.delete"), systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(L("common.more"))
            }
        }
        .sheet(item: $newItem) { item in
            ItemEditorView(item: item, isNew: true).environmentObject(store)
        }
        .sheet(item: $editSubject) { subject in
            SubjectEditor(subject: subject).environmentObject(store)
        }
        .confirmationDialog(L("subject.delete.title"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("common.delete"), role: .destructive) {
                store.deleteSubject(subjectID)
                dismiss()
            }
        } message: {
            Text(L("subject.delete.message"))
        }
    }

    private var header: some View {
        let all = store.items(in: subjectID)
        let learned = all.filter(\.isIntroduced)
        let reviewed = learned.filter { $0.card.state == .review }
        let predicted = reviewed.isEmpty ? nil : reviewed.map { store.retrievability(of: $0) }.reduce(0, +) / Double(reviewed.count)
        return VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(title: L("subject.items"), value: "\(all.count)", systemImage: "square.stack")
                StatTile(title: L("subject.learned"), value: "\(learned.count)", systemImage: "checkmark.circle", tint: Theme.success)
                StatTile(title: L("analytics.predicted"), value: Formatters.percent(predicted), systemImage: "function", tint: Theme.violet)
            }
            HStack(spacing: 10) {
                Button { router.start(SessionRequest(mode: .learn, subjectID: subjectID)) } label: {
                    Label(StudyMode.learn.title, systemImage: "book")
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                Button { router.start(SessionRequest(mode: .remember, subjectID: subjectID)) } label: {
                    Label(StudyMode.remember.title, systemImage: "brain.head.profile")
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .disabled(learned.isEmpty)
            }
            NavigationLink { KnowledgeGraphView(subjectID: subjectID) } label: {
                Label(L("graph.title"), systemImage: "point.3.connected.trianglepath.dotted")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: Theme.violet))
        }
    }

    private func filterChip(_ state: MemoryState?, title: String) -> some View {
        Button {
            stateFilter = state
            Haptics.selection()
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(stateFilter == state ? Color.white : Color.primary)
                .background(stateFilter == state ? Theme.accent : Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
