import SwiftUI

/// Reviews items on the fixed schedule one at a time: try to recall, reveal, then
/// "I remembered" (next interval, or mastered after the last) or "I forgot" (one step back).
struct MemoReviewView: View {
    @EnvironmentObject private var store: MemoraStore
    @Environment(\.dismiss) private var dismiss

    var itemIDs: [UUID]?

    @State private var queue: [UUID] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var masteredNow: LearningItem?
    @State private var reviewed = 0
    @State private var masteredCount = 0
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let mastered = masteredNow {
                        masteredCard(mastered)
                    } else if let item = currentItem {
                        reviewCard(item)
                    } else if loaded {
                        finishedCard
                    }
                }
                .padding(Theme.padding)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .memoraScreen()
            .navigationTitle(L("memo.review.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { close() }
                }
                if !queue.isEmpty && currentItem != nil {
                    ToolbarItem(placement: .principal) {
                        Text("\(min(index + 1, queue.count)) / \(queue.count)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private var currentItem: LearningItem? {
        guard index < queue.count else { return nil }
        return store.item(queue[index])
    }

    // MARK: Cards

    private func reviewCard(_ item: LearningItem) -> some View {
        VStack(spacing: 14) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if let subject = store.subject(item.subjectID) {
                            Text(subject.name).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                        Spacer()
                        StepDots(done: MemoSchedule.progress(item))
                    }
                    Text(item.prompt)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if revealed {
                        Divider()
                        Text(item.answer)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        if !item.explanation.isEmpty {
                            Text(item.explanation).font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(item.examples, id: \.self) { example in
                            Label(example, systemImage: "lightbulb").font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(item.mnemonics) { mnemonic in
                            Label(mnemonic.content, systemImage: "sparkles").font(.callout).foregroundStyle(Theme.accent)
                        }
                    } else {
                        Text(L("memo.review.tryFirst")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if revealed {
                HStack(spacing: 10) {
                    Button { answer(item, remembered: false) } label: {
                        Label(L("memo.review.forgot"), systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: Theme.warning))
                    Button { answer(item, remembered: true) } label: {
                        Label(L("memo.review.remembered"), systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                }
                Text(nextHint(item)).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { revealed = true }
                    Haptics.tap()
                } label: {
                    Label(L("memo.review.show"), systemImage: "eye").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            }
        }
    }

    private func masteredCard(_ item: LearningItem) -> some View {
        GlassCard {
            VStack(spacing: 12) {
                Text("🎉").font(.system(size: 56))
                Text(MemoSchedule.masteredLabel(kind: item.memoKind)).font(.title3.weight(.bold)).multilineTextAlignment(.center)
                Text(item.title).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(L("common.continue")) {
                    masteredNow = nil
                    advance()
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var finishedCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Theme.success)
                Text(reviewed == 0 ? L("memo.review.nothing") : L("memo.review.done")).font(.title3.weight(.bold))
                if reviewed > 0 {
                    Text(LF("memo.review.summary", reviewed)).font(.callout).foregroundStyle(.secondary)
                }
                if masteredCount > 0 {
                    Text(LF("memo.review.masteredCount", masteredCount)).font(.callout).foregroundStyle(Theme.success)
                }
                Text(L("memo.review.nextNote")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(L("common.close")) { close() }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: Logic

    private func load() {
        guard !loaded else { return }
        let now = Date()
        if let ids = itemIDs, !ids.isEmpty {
            // From a reminder: those items (not yet mastered), whatever their due time.
            queue = ids.filter { id in store.item(id).map { $0.masteredAt == nil } ?? false }
        } else {
            queue = store.db.items
                .filter { MemoSchedule.isDue($0, now: now) }
                .sorted { $0.card.due < $1.card.due }
                .map(\.id)
        }
        loaded = true
    }

    private func nextHint(_ item: LearningItem) -> String {
        let step = min(max(item.memoStep ?? 0, 0), MemoSchedule.stepCount - 1)
        if step + 1 >= MemoSchedule.stepCount { return L("memo.review.lastOne") }
        return LF("memo.review.nextIn", MemoSchedule.intervalName(step + 1))
    }

    private func answer(_ item: LearningItem, remembered: Bool) {
        var updated = item
        let mastered = MemoSchedule.review(&updated, remembered: remembered)
        store.upsertItem(updated)
        reviewed += 1
        if mastered {
            masteredCount += 1
            masteredNow = updated
            Haptics.success()
        } else {
            remembered ? Haptics.success() : Haptics.tap()
            advance()
        }
    }

    private func advance() {
        revealed = false
        index += 1
    }

    private func close() {
        Task { await ReminderService.shared.refresh(store: store) }
        dismiss()
    }
}

/// Five dots: one per scheduled reminder, filled when done.
struct StepDots: View {
    var done: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<MemoSchedule.stepCount, id: \.self) { step in
                Circle()
                    .fill(step < done ? Theme.success : Color.secondary.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityLabel(LF("memo.steps.a11y", done, MemoSchedule.stepCount))
    }
}
