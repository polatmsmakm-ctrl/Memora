import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if store.db.items.isEmpty {
                        GlassCard {
                            EmptyStateView(systemImage: "square.and.arrow.down", title: L("home.empty.title"), message: L("home.empty.message"),
                                           actionTitle: L("home.empty.action")) { router.openImport() }
                        }
                        .guideAnchor(.homeSummary)
                    } else {
                        todayCard
                            .guideAnchor(.homeSummary)
                        statesCard
                        rescueCard
                        diagnosisCard
                        learnCard
                        quickModes
                    }
                }
                .padding(Theme.padding)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .memoraScreen()
            .navigationTitle(L("tab.home"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var now: Date { Date() }
    private var due: [LearningItem] { store.dueItems().filter { !store.experimentLockedItemIDs.contains($0.id) } }
    private var minutes: Int {
        let seconds = AnalyticsEngine.averageSecondsPerReview(logs: store.db.reviewLogs)
        return due.isEmpty ? 0 : max(1, Int((Double(due.count) * seconds / 60).rounded(.up)))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting).font(.memoraLargeTitle)
                Text(L("home.subtitle")).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { router.openImport() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("library.import"))
            .guideAnchor(.addMaterial)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<12: return L("home.greeting.morning")
        case 12..<18: return L("home.greeting.afternoon")
        default: return L("home.greeting.evening")
        }
    }

    private var todayCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(due.count)").font(.system(size: 52, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(L("home.due.label")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !due.isEmpty {
                        Chip(text: LF("home.minutes", minutes), systemImage: "clock")
                    }
                }
                Text(due.isEmpty ? nextDueText : L("home.due.explain")).font(.footnote).foregroundStyle(.secondary)
                Button {
                    router.start(SessionRequest(mode: .smartReview))
                } label: {
                    Label(L("home.startReview"), systemImage: "sparkles")
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .disabled(due.isEmpty)
            }
        }
    }

    private var nextDueText: String {
        let next = store.db.items.filter { $0.isIntroduced && !$0.isSuspended }.map(\.card.due).filter { $0 > now }.min()
        guard let next else { return L("home.due.none") }
        return LF("home.due.next", Formatters.relative(next))
    }

    private var statesCard: some View {
        let counts = Dictionary(grouping: store.db.items) { store.memoryState(of: $0) }.mapValues(\.count)
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: L("home.states"), subtitle: L("home.states.subtitle"), systemImage: "square.stack.3d.up")
                ForEach(MemoryState.allCases) { state in
                    let count = counts[state] ?? 0
                    HStack(spacing: 10) {
                        Image(systemName: state.systemImage).foregroundStyle(Theme.color(for: state)).frame(width: 22)
                        Text(state.title).font(.callout)
                        Spacer()
                        ProgressBar(value: store.db.items.isEmpty ? 0 : Double(count) / Double(store.db.items.count), tint: Theme.color(for: state))
                            .frame(width: 90)
                        Text("\(count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private var rescueCard: some View {
        let weak = store.db.items.filter { store.memoryState(of: $0) == .weak }
        if weak.count >= 2 {
            GlassCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lifepreserver").font(.title2).foregroundStyle(Theme.danger)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LF("home.weak.title", weak.count)).font(.headline)
                        Text(L("home.weak.body")).font(.footnote).foregroundStyle(.secondary)
                        Button(StudyMode.memoryRescue.title) { router.start(SessionRequest(mode: .memoryRescue)) }
                            .buttonStyle(SecondaryButtonStyle(tint: Theme.danger))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var diagnosisCard: some View {
        let diagnoses = PrerequisiteAnalyzer.diagnoses(items: store.db.items, logs: store.db.reviewLogs, links: store.db.links,
                                                       scheduler: store.scheduler, now: now)
        if let first = diagnoses.first {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L("home.prereq.title"), systemImage: "square.stack.3d.down.right").font(.headline).foregroundStyle(Theme.warning)
                    Text(LF("home.prereq.body", first.item.title, first.weakPrerequisites.map(\.title).joined(separator: "، ")))
                        .font(.footnote)
                    Button(L("home.prereq.action")) {
                        router.start(SessionRequest(mode: .remember, itemIDs: first.weakPrerequisites.map(\.id) + [first.item.id]))
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.warning))
                }
            }
        }
    }

    @ViewBuilder
    private var learnCard: some View {
        let newCount = store.newItems(subjectID: nil).count
        if newCount > 0 {
            GlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "book").font(.title2).foregroundStyle(Theme.violet)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LF("home.new.title", newCount)).font(.headline)
                        Text(L("home.new.body")).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("home.new.action")) { router.selectedTab = .learn }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private var quickModes: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            ModeTile(mode: .quickDaily) { router.start(SessionRequest(mode: .quickDaily)) }
            ModeTile(mode: .successiveRelearning) { router.start(SessionRequest(mode: .successiveRelearning)) }
            ModeTile(mode: .blindRecall) { router.start(SessionRequest(mode: .blindRecall)) }
            ModeTile(mode: .longTerm) { router.start(SessionRequest(mode: .longTerm)) }
        }
    }
}
