import SwiftUI

struct LearnHubView: View {
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if store.db.subjects.isEmpty {
                        EmptyStateView(systemImage: "book", title: L("learn.hub.empty.title"), message: L("learn.hub.empty.message"),
                                       actionTitle: L("home.empty.action")) { router.openImport() }
                    } else {
                        allowanceCard
                        ForEach(store.db.subjects.filter { !$0.isArchived }) { subject in
                            SubjectLearnCard(subject: subject)
                        }
                        SectionHeader(title: L("learn.hub.understand"), subtitle: L("learn.hub.understand.subtitle"), systemImage: "magnifyingglass")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
                            ModeTile(mode: .deepUnderstanding) { router.start(SessionRequest(mode: .deepUnderstanding)) }
                            ModeTile(mode: .transfer) { router.start(SessionRequest(mode: .transfer)) }
                        }
                        NavigationLink {
                            MemoryPalaceListView()
                        } label: {
                            GlassCard {
                                HStack(spacing: 12) {
                                    Image(systemName: "building.columns").font(.title2).foregroundStyle(Theme.violet)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L("palace.title")).font(.headline)
                                        Text(L("palace.subtitle")).font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.padding)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .memoraScreen()
            .navigationTitle(L("tab.learn"))
        }
    }

    private var allowanceCard: some View {
        let builder = SessionBuilder(scheduler: store.scheduler, settings: store.settings, now: Date())
        let remaining = builder.remainingNewAllowance(db: store.db)
        return GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LF("learn.hub.allowance", remaining, store.settings.dailyNewLimit)).font(.headline)
                    Text(L("learn.hub.allowance.body")).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SubjectLearnCard: View {
    var subject: Subject
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        let items = store.items(in: subject.id)
        let unseen = items.filter { $0.card.state == .new && !$0.isSuspended }
        let notPretested = unseen.filter { $0.pretestedAt == nil }
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: subject.symbol).foregroundStyle(Theme.accent)
                    Text(subject.name).font(.headline)
                    Spacer()
                    Chip(text: LF("learn.hub.newCount", unseen.count), tint: Theme.violet)
                }
                if unseen.isEmpty {
                    Text(L("learn.hub.allLearned")).font(.footnote).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        NavigationLink {
                            PriorKnowledgeView(subjectID: subject.id)
                        } label: {
                            Label(L("prior.title"), systemImage: "map")
                        }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                        if store.settings.pretestNewTopics && !notPretested.isEmpty {
                            Button {
                                router.start(SessionRequest(mode: .pretest, subjectID: subject.id, limit: min(10, notPretested.count)))
                            } label: {
                                Label(StudyMode.pretest.title, systemImage: StudyMode.pretest.systemImage)
                            }
                            .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: Theme.violet))
                        }
                    }
                    Button {
                        router.start(SessionRequest(mode: .learn, subjectID: subject.id))
                    } label: {
                        Label(L("learn.hub.start"), systemImage: "book")
                    }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                }
            }
        }
    }
}
