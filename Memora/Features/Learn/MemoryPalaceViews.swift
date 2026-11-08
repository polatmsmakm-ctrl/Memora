import SwiftUI

/// Method of loci: build a route of familiar places, place one item at each,
/// then walk the route recalling what is stored at every stop.
struct MemoryPalaceListView: View {
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter
    @State private var editing: MemoryPalace?

    var body: some View {
        List {
            Section {
                Text(L("palace.explain")).font(.footnote).foregroundStyle(.secondary)
            }
            if store.db.palaces.isEmpty {
                Section {
                    EmptyStateView(systemImage: "building.columns", title: L("palace.empty.title"), message: L("palace.empty.message"))
                }
                .listRowBackground(Color.clear)
            }
            ForEach(store.db.palaces) { palace in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(palace.name).font(.headline)
                        Text(LF("palace.loci", palace.loci.count, palace.loci.filter { $0.itemID != nil }.count))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(L("palace.walk")) {
                                router.start(SessionRequest(mode: .palaceWalk, palaceID: palace.id))
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(!palace.loci.contains { $0.itemID != nil })
                            Spacer()
                            Button(L("common.edit")) { editing = palace }
                                .buttonStyle(SecondaryButtonStyle(tint: .secondary))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.surface)
            }
            .onDelete { offsets in
                for index in offsets { store.deletePalace(store.db.palaces[index].id) }
            }
        }
        .memoraScreen()
        .navigationTitle(L("palace.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = MemoryPalace(name: "") } label: { Image(systemName: "plus") }
                    .accessibilityLabel(L("palace.new"))
            }
        }
        .sheet(item: $editing) { palace in
            MemoryPalaceEditor(palace: palace)
                .environmentObject(store)
        }
    }
}

struct MemoryPalaceEditor: View {
    @State var palace: MemoryPalace
    @EnvironmentObject private var store: MemoraStore
    @Environment(\.dismiss) private var dismiss
    @State private var newLocus = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(L("palace.name")) {
                    TextField(L("palace.name.placeholder"), text: $palace.name)
                    TextField(L("palace.details"), text: $palace.details, axis: .vertical)
                }
                Section(L("palace.route")) {
                    ForEach($palace.loci) { $locus in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(L("palace.locus"), text: $locus.name)
                                .font(.headline)
                            Picker(L("palace.item"), selection: $locus.itemID) {
                                Text(L("palace.noItem")).tag(UUID?.none)
                                ForEach(store.db.items.sorted { $0.title < $1.title }) { item in
                                    Text(item.title).tag(Optional(item.id))
                                }
                            }
                        }
                    }
                    .onDelete { palace.loci.remove(atOffsets: $0) }
                    .onMove { palace.loci.move(fromOffsets: $0, toOffset: $1) }
                    HStack {
                        TextField(L("palace.newLocus"), text: $newLocus)
                        Button {
                            let name = newLocus.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            palace.loci.append(Locus(name: name))
                            newLocus = ""
                        } label: { Image(systemName: "plus.circle.fill") }
                        .disabled(TextNormalizer.isBlank(newLocus))
                    }
                }
                Section {
                    Text(L("palace.tip")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .memoraScreen()
            .navigationTitle(palace.name.isEmpty ? L("palace.new") : palace.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.save")) {
                        store.upsertPalace(palace)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(TextNormalizer.isBlank(palace.name))
                }
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
            .keyboardDoneButton()
        }
    }
}
