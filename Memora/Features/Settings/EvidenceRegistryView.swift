import SwiftUI

struct EvidenceRegistryView: View {
    @State private var search = ""

    private var entries: [EvidenceEntry] {
        let query = TextNormalizer.normalize(search)
        guard !query.isEmpty else { return EvidenceRegistry.entries }
        return EvidenceRegistry.entries.filter {
            TextNormalizer.normalize($0.name.ar + " " + $0.name.en + " " + $0.principle.text).contains(query)
        }
    }

    var body: some View {
        List {
            Section {
                Text(L("evidence.intro")).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                NavigationLink { EvidenceDetailView(entry: entry) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name.text).font(.headline)
                        HStack {
                            Chip(text: entry.strength.title, tint: tint(entry.strength))
                            Text(LF("evidence.refs", entry.citations.count)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .memoraScreen()
        .navigationTitle(L("settings.evidence"))
        .searchable(text: $search)
    }

    private func tint(_ strength: EvidenceStrength) -> Color {
        switch strength {
        case .strong: return Theme.success
        case .moderate: return Theme.accent
        case .emerging: return Theme.warning
        case .limited: return .secondary
        }
    }
}

struct EvidenceDetailView: View {
    let entry: EvidenceEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(entry.name.text).font(.memoraTitle)
                Chip(text: entry.strength.title)
                block(L("evidence.principle"), entry.principle.text, "lightbulb")
                block(L("evidence.implementation"), entry.implementation.text, "gearshape.2")
                block(L("evidence.limitations"), entry.limitations.text, "exclamationmark.triangle")
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L("evidence.references"), systemImage: "text.book.closed").font(.headline)
                        ForEach(entry.citations, id: \.self) { citation in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(citation.reference).font(.caption).textSelection(.enabled)
                                    .environment(\.layoutDirection, .leftToRight)
                                if let url = citation.url {
                                    Link("doi:" + (citation.doi ?? ""), destination: url).font(.caption2)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.padding)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .memoraScreen()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ title: String, _ body: String, _ icon: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon).font(.headline)
                Text(body).font(.callout)
            }
        }
    }
}
