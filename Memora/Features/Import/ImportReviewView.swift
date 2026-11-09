import SwiftUI

/// The learner approves, edits or rejects every proposed unit before anything is saved.
/// Units that fail the grounding check start unselected and are marked.
struct ImportReviewView: View {
    @ObservedObject var vm: ImportViewModel
    var onSave: () -> Void
    @State private var editingID: UUID?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LF("import.review.header", vm.units.count, vm.includedCount)).font(.headline)
                    Text(L("import.review.body")).font(.caption).foregroundStyle(.secondary)
                        .featureTip(.importReview)
                    if let notice = vm.notice {
                        Label(notice, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warning)
                    }
                    if !vm.relationships.isEmpty {
                        Label(LF("import.review.links", vm.relationships.count), systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 14) {
                        Button { vm.backToText() } label: { Label(L("import.back"), systemImage: "chevron.backward") }
                        Spacer()
                        Button(L("import.selectAll")) { vm.setAllIncluded(true) }
                            .disabled(vm.includedCount == vm.units.count)
                        Button(L("import.selectNone")) { vm.setAllIncluded(false) }
                            .disabled(vm.includedCount == 0)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
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
                            Button(L("common.done")) { editingID = nil }
                                .font(.callout.weight(.semibold))
                                .buttonStyle(.borderless)
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
                            // Borderless so a tap on the row doesn't trigger this button too.
                            Button(L("common.edit")) { editingID = unit.id }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.surface)
            }

            Section {
                Button(action: onSave) {
                    Text(LF("import.saveN", vm.includedCount))
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .disabled(vm.includedCount == 0)
            }
            .listRowBackground(Color.clear)
        }
        .scrollDismissesKeyboard(.interactively)
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
