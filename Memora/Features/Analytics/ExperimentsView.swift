import SwiftUI
import Charts

/// Personal learning experiments: two methods on comparable material, then a delayed
/// free-recall test. Results are descriptive and explicitly not scientific proof.
struct ExperimentsView: View {
    @EnvironmentObject private var store: MemoraStore
    @State private var showNew = false

    var body: some View {
        List {
            Section {
                Text(L("experiments.explain")).font(.footnote).foregroundStyle(.secondary)
                    .featureTip(.experiments)
            }
            if store.db.experiments.isEmpty {
                Section {
                    EmptyStateView(systemImage: "flask", title: L("experiments.empty.title"), message: L("experiments.empty.message"),
                                   actionTitle: L("experiments.new")) { showNew = true }
                }
                .listRowBackground(Color.clear)
            }
            ForEach(store.db.experiments.sorted { $0.createdAt > $1.createdAt }) { experiment in
                NavigationLink { ExperimentDetailView(experimentID: experiment.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(experiment.name).font(.headline)
                        Text("\(experiment.methodA.title)  vs  \(experiment.methodB.title)").font(.caption).foregroundStyle(.secondary)
                        Text(status(experiment)).font(.caption2).foregroundStyle(Theme.accent)
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .onDelete { offsets in
                let sorted = store.db.experiments.sorted { $0.createdAt > $1.createdAt }
                for index in offsets { store.deleteExperiment(sorted[index].id) }
            }
        }
        .memoraScreen()
        .navigationTitle(L("experiments.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: { Image(systemName: "plus") }.accessibilityLabel(L("experiments.new"))
            }
        }
        .sheet(isPresented: $showNew) { NewExperimentView().environmentObject(store) }
    }

    private func status(_ e: Experiment) -> String {
        if e.isCompleted { return L("experiments.status.done") }
        if e.isTestAvailable() { return L("experiments.status.testReady") }
        if e.practiceDone, let date = e.testAvailableDate { return LF("experiments.status.waiting", Formatters.relative(date)) }
        return LF("experiments.status.practice", e.practiceCount(.a), e.practiceCount(.b), e.practiceSessionsPerCondition)
    }
}

struct NewExperimentView: View {
    @EnvironmentObject private var store: MemoraStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hypothesis = ""
    @State private var subjectID: UUID?
    @State private var methodA: ExperimentMethod = .activeRecall
    @State private var methodB: ExperimentMethod = .rereading
    @State private var itemsPerCondition = 6
    @State private var sessions = 2
    @State private var delay = 7

    private var available: [LearningItem] {
        let locked = store.experimentLockedItemIDs
        return store.items(in: subjectID)
            .filter { !locked.contains($0.id) && !$0.isSuspended && $0.card.state != .review }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("experiments.form.basics")) {
                    TextField(L("experiments.form.name"), text: $name)
                    TextField(L("experiments.form.hypothesis"), text: $hypothesis, axis: .vertical)
                    Picker(L("common.subject"), selection: $subjectID) {
                        Text(L("common.allSubjects")).tag(UUID?.none)
                        ForEach(store.db.subjects) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section(L("experiments.form.methods")) {
                    Picker("A", selection: $methodA) { ForEach(ExperimentMethod.allCases) { Text($0.title).tag($0) } }
                    Picker("B", selection: $methodB) { ForEach(ExperimentMethod.allCases) { Text($0.title).tag($0) } }
                }
                Section {
                    Stepper(LF("experiments.form.items", itemsPerCondition), value: $itemsPerCondition, in: 3...30)
                    Stepper(LF("experiments.form.sessions", sessions), value: $sessions, in: 1...5)
                    Stepper(LF("experiments.form.delay", delay), value: $delay, in: 1...60)
                } header: { Text(L("experiments.form.design")) } footer: {
                    Text(LF("experiments.form.available", available.count, itemsPerCondition * 2))
                }
                Section {
                    Text(L("experiments.form.note")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .memoraScreen()
            .navigationTitle(L("experiments.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.create")) { create() }
                        .disabled(TextNormalizer.isBlank(name) || methodA == methodB || available.count < itemsPerCondition * 2)
                }
            }
            .keyboardDoneButton()
        }
    }

    /// Alternating assignment of comparable, consecutive items keeps both conditions balanced.
    private func create() {
        let chosen = Array(available.prefix(itemsPerCondition * 2))
        let a = chosen.enumerated().filter { $0.offset % 2 == 0 }.map(\.element.id)
        let b = chosen.enumerated().filter { $0.offset % 2 == 1 }.map(\.element.id)
        let experiment = Experiment(name: name, hypothesis: hypothesis, subjectID: subjectID, methodA: methodA, methodB: methodB,
                                    itemIDsA: a, itemIDsB: b, practiceSessionsPerCondition: sessions, testDelayDays: delay)
        store.upsertExperiment(experiment)
        Haptics.success()
        dismiss()
    }
}

struct ExperimentDetailView: View {
    let experimentID: UUID
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter

    private var experiment: Experiment? { store.db.experiments.first { $0.id == experimentID } }

    var body: some View {
        ScrollView {
            if let e = experiment {
                VStack(alignment: .leading, spacing: 16) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(e.name).font(.memoraTitle)
                            if !e.hypothesis.isEmpty { Text(e.hypothesis).font(.callout).foregroundStyle(.secondary) }
                            Text(LF("experiments.detail.design", e.itemIDsA.count, e.practiceSessionsPerCondition, e.testDelayDays))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(ExperimentCondition.allCases) { condition in
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(condition.title).font(.title3.weight(.bold)).foregroundStyle(Theme.accent)
                                    Text(e.method(condition).title).font(.headline)
                                    Spacer()
                                    Text("\(e.practiceCount(condition))/\(e.practiceSessionsPerCondition)").font(.callout.monospacedDigit())
                                }
                                if !e.isCompleted && e.practiceCount(condition) < e.practiceSessionsPerCondition {
                                    Button(L("experiments.practice")) {
                                        router.start(SessionRequest(mode: .experiment, experimentID: e.id, experimentCondition: condition, experimentPhase: .practice))
                                    }
                                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                                }
                            }
                        }
                    }
                    testCard(e)
                    if e.isCompleted { resultsCard(e) }
                }
                .padding(Theme.padding)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .memoraScreen()
        .navigationTitle(L("experiments.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func testCard(_ e: Experiment) -> some View {
        if !e.isCompleted {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L("experiments.test"), systemImage: "hourglass").font(.headline)
                    if e.isTestAvailable() {
                        Button(L("experiments.test.start")) {
                            router.start(SessionRequest(mode: .experiment, experimentID: e.id, experimentPhase: .test))
                        }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    } else if let date = e.testAvailableDate {
                        Text(LF("experiments.test.on", Formatters.date(date, time: .short))).font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text(L("experiments.test.afterPractice")).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func resultsCard(_ e: Experiment) -> some View {
        let a = e.summary(.a), b = e.summary(.b)
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("experiments.results"), systemImage: "chart.bar").font(.headline)
                Chart {
                    BarMark(x: .value("cond", "A · " + e.methodA.title), y: .value("score", a?.mean ?? 0)).foregroundStyle(Theme.accent)
                    BarMark(x: .value("cond", "B · " + e.methodB.title), y: .value("score", b?.mean ?? 0)).foregroundStyle(Theme.violet)
                }
                .chartYScale(domain: 0...1)
                .frame(height: 170)
                Text(LF("experiments.results.line", Formatters.percent(a?.mean), a?.n ?? 0, Formatters.percent(b?.mean), b?.n ?? 0))
                    .font(.callout)
                Text(L("experiments.results.caveat")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
