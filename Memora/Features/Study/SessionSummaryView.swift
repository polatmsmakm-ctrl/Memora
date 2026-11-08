import SwiftUI

struct SessionSummaryView: View {
    var summary: SessionSummary
    var mode: StudyMode
    var onDone: () -> Void
    @EnvironmentObject private var store: MemoraStore

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(Theme.success)
                Text(L("summary.title")).font(.memoraTitle)
                Text(mode.title).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 20)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(title: L("summary.attempts"), value: "\(summary.attempts)", systemImage: "list.number")
                StatTile(title: L("summary.accuracy"), value: Formatters.percent(summary.accuracy), systemImage: "target", tint: Theme.success)
                StatTile(title: L("summary.partial"), value: "\(summary.partial)", systemImage: "circle.lefthalf.filled", tint: Theme.warning)
                StatTile(title: L("summary.incorrect"), value: "\(summary.incorrect)", systemImage: "xmark.circle", tint: Theme.danger)
            }

            if let confidence = summary.meanConfidence, let accuracy = summary.accuracy, summary.confidenceCount >= 3 {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(L("summary.calibration"), systemImage: "gauge.with.dots.needle.50percent").font(.headline)
                        Text(LF("summary.calibration.body", Formatters.percent(confidence), Formatters.percent(accuracy))).font(.callout)
                        Text(CalibrationAnalyzer.label(for: confidence - accuracy).title).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if !summary.errors.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L("summary.errors"), systemImage: "exclamationmark.triangle").font(.headline)
                        ForEach(summary.errors.sorted { $0.value > $1.value }, id: \.key) { category, count in
                            HStack {
                                Label(category.title, systemImage: category.systemImage).font(.callout)
                                Spacer()
                                Text("\(count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if summary.followUps > 0 {
                Text(LF("summary.followUps", summary.followUps)).font(.footnote).foregroundStyle(.secondary)
            }
            if summary.restudied > 0 {
                Text(LF("summary.restudied", summary.restudied)).font(.footnote).foregroundStyle(.secondary)
            }

            if let next = nextDue {
                Text(LF("summary.nextDue", Formatters.relative(next))).font(.footnote).foregroundStyle(.secondary)
            }

            Button(L("common.done"), action: onDone)
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .padding(.top, 8)
        }
    }

    private var nextDue: Date? {
        store.db.items.filter { summary.itemIDs.contains($0.id) && $0.isIntroduced }.map(\.card.due).min()
    }
}
