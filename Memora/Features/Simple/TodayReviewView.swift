import SwiftUI

/// The Review tab: what's due now on the fixed schedule, what's in progress (with the
/// next reminder time) and what's already mastered.
struct TodayReviewView: View {
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if store.db.items.isEmpty {
                        EmptyStateView(systemImage: "rectangle.on.rectangle.angled", title: L("today.empty.title"),
                                       message: L("today.empty.message"), actionTitle: L("today.empty.action")) {
                            router.selectedTab = .add
                        }
                    } else {
                        TimelineView(.periodic(from: Date(), by: 60)) { context in
                            content(now: context.date)
                        }
                    }
                }
                .padding(Theme.padding)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .memoraScreen()
            .navigationTitle(L("today.title"))
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let groups = SubjectProgress.build(store: store, now: now)
        let dueCount = groups.reduce(0) { $0 + $1.due }
        let notStarted = store.db.items.filter { $0.masteredAt == nil && !$0.isIntroduced && !$0.isSuspended }

        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "bell.badge").foregroundStyle(Theme.accent)
                    Text(L("today.due")).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(dueCount)").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                }
                if dueCount > 0 {
                    Button { router.openItems(nil) } label: { Text(L("today.due.go")).frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                } else {
                    Text(nextReminderText(groups)).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }

        if !notStarted.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(LF("memo.notStarted", notStarted.count)).font(.callout)
                    Button(L("memo.notStarted.go")) { start(notStarted) }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                }
            }
        }

        let active = groups.filter { !$0.isMastered }
        if !active.isEmpty {
            sectionHeader(L("memo.inProgress"))
            ForEach(active) { group in row(group, now: now) }
        }

        let mastered = groups.filter(\.isMastered)
        if !mastered.isEmpty {
            sectionHeader(L("memo.masteredSection"))
            ForEach(mastered) { group in row(group, now: now) }
        }

        HStack(spacing: 16) {
            if store.db.items.contains(where: \.isIntroduced) {
                Button(L("today.exam.go")) { router.start(SessionRequest(mode: .exam)) }
            }
            Button(L("today.moreModes")) { router.openAdvanced(.reviewModes) }
        }
        .font(.footnote)
        .padding(.top, 4)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }

    private func row(_ group: SubjectProgress, now: Date) -> some View {
        Button {
            if group.due > 0 { router.openItems(group.dueIDs) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    if group.isMastered {
                        Label(MemoSchedule.masteredLabel(kind: group.kind, plural: group.count > 1), systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.success)
                    } else if group.due > 0 {
                        Text(LF("memo.row.due", group.due)).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    } else if let next = group.nextDue {
                        Text(LF("memo.row.next", next.formatted(.relative(presentation: .named))))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if group.count > 1 {
                        Text(LF("memo.row.count", group.count)).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                StepDots(done: group.step)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func nextReminderText(_ groups: [SubjectProgress]) -> String {
        guard let next = groups.compactMap(\.nextDue).min() else { return L("today.done.message") }
        return LF("memo.nextReminder", next.formatted(.relative(presentation: .named)))
    }

    /// Older cards that never started: put them on the fixed schedule.
    private func start(_ items: [LearningItem]) {
        for item in items {
            var copy = item
            MemoSchedule.start(&copy)
            store.upsertItem(copy)
        }
        Task {
            let service = ReminderService.shared
            await service.refreshAuthorization()
            if service.authorization == .notDetermined { await service.requestAuthorization() }
            await service.refresh(store: store)
        }
    }
}

/// One subject (a rule, poem, lesson or word set) with its schedule progress.
struct SubjectProgress: Identifiable {
    var id: UUID
    var name: String
    var kind: String?
    var count: Int
    var due: Int
    var dueIDs: [UUID]
    var step: Int
    var nextDue: Date?
    var isMastered: Bool

    static func build(store: MemoraStore, now: Date) -> [SubjectProgress] {
        let started = store.db.items.filter { $0.isIntroduced && !$0.isSuspended }
        let bySubject = Dictionary(grouping: started, by: \.subjectID)
        return bySubject.compactMap { subjectID, items -> SubjectProgress? in
            guard !items.isEmpty else { return nil }
            let active = items.filter { $0.masteredAt == nil }
            let dueItems = active.filter { MemoSchedule.isDue($0, now: now) }
            return SubjectProgress(id: subjectID,
                                   name: store.subject(subjectID)?.name ?? items[0].title,
                                   kind: items.compactMap(\.memoKind).first,
                                   count: items.count,
                                   due: dueItems.count,
                                   dueIDs: dueItems.map(\.id),
                                   step: items.map(MemoSchedule.progress).min() ?? 0,
                                   nextDue: active.map(\.card.due).filter { $0 > now }.min(),
                                   isMastered: active.isEmpty)
        }
        .sorted { a, b in
            if a.due != b.due { return a.due > b.due }
            return (a.nextDue ?? .distantFuture) < (b.nextDue ?? .distantFuture)
        }
    }
}
