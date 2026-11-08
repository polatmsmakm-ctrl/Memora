import SwiftUI

/// The learner approves, edits or rejects every proposed unit before anything is saved.
/// Units that fail the grounding check start unselected and are marked.
struct ImportReviewView: View {
    @ObservedObject var vm: ImportViewModel
    @State private var editingID: UUID?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LF("import.review.header", vm.units.count, vm.includedCount)).font(.headline)
                    Text(L("import.review.body")).font(.caption).foregroundStyle(.secondary)
                    if let notice = vm.notice {
                        Label(notice, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warning)
                    }
                    if !vm.relationships.isEmpty {
                        Label(LF("import.review.links", vm.relationships.count), systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(Color.clear)

            ForEach($vm.units) { $unit in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Toggle(isOn: $unit.include) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(unit.title).font(.headline)
                                    HStack(spacing: 6) {
                                        Chip(text: unit.kind.title, tint: .secondary)
                                        OriginBadge(origin: unit.origin)
                                        groundingBadge(unit.grounding)
                                    }
                                }
                            }
                        }
                        if editingID == unit.id {
                            TextField(L("editor.title"), text: $unit.title)
                            TextField(L("editor.prompt"), text: $unit.prompt, axis: .vertical)
                            TextField(L("editor.answer"), text: $unit.answer, axis: .vertical)
                            TextField(L("editor.explanation"), text: $unit.explanation, axis: .vertical)
                            Button(L("common.done")) { editingID = nil }.font(.callout.weight(.semibold))
                        } else {
                            Text(unit.prompt).font(.callout.weight(.medium))
                            Text(unit.answer).font(.callout).foregroundStyle(.secondary)
                            if !unit.keyPoints.isEmpty {
                                Text(unit.keyPoints.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.violet)
                            }
                            if !unit.sourceQuote.isEmpty {
                                Text("“" + unit.sourceQuote + "”").font(.caption2).italic().foregroundStyle(.tertiary).lineLimit(3)
                            }
                            if let issues = unit.grounding?.issues, !issues.isEmpty {
                                ForEach(issues, id: \.self) { issue in
                                    Label(issue, systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(Theme.warning)
                                }
                            }
                            Button(L("common.edit")) { editingID = unit.id }.font(.caption.weight(.semibold))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.surface)
            }
        }
    }

    @ViewBuilder
    private func groundingBadge(_ report: GroundingReport?) -> some View {
        if let report {
            if report.isGrounded {
                Chip(text: L("import.grounded"), systemImage: "checkmark.shield", tint: Theme.success)
            } else {
                Chip(text: L("import.unverified"), systemImage: "exclamationmark.shield", tint: Theme.warning)
            }
        }
    }
}
