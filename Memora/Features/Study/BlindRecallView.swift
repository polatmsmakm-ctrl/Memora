import SwiftUI

/// Blind recall: only the topic name is shown; the learner reconstructs everything
/// they know, and every learned item of the topic is graded against the free text.
struct BlindRecallView: View {
    var subjectID: UUID?
    @EnvironmentObject private var store: MemoraStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSubject: UUID?
    @State private var text = ""
    @State private var confidence: ConfidenceLevel?
    @State private var results: [(item: LearningItem, evaluation: AnswerEvaluation)] = []
    @State private var phase: Phase = .writing
    @State private var startedAt = Date()
    @State private var sessionID = UUID()

    enum Phase { case writing, results, saved }

    private var subjectIDResolved: UUID? { selectedSubject ?? subjectID ?? store.db.subjects.first?.id }
    private var topicItems: [LearningItem] {
        store.items(in: subjectIDResolved).filter { $0.isIntroduced && !$0.isSuspended }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    switch phase {
                    case .writing: writingView
                    case .results, .saved: resultsView
                    }
                }
                .padding(Theme.padding)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .memoraScreen()
            .navigationTitle(StudyMode.blindRecall.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(L("common.close"))
                }
            }
            .keyboardDoneButton()
        }
    }

    @ViewBuilder
    private var writingView: some View {
        if store.db.subjects.isEmpty || topicItems.isEmpty && subjectID != nil {
            EmptyStateView(systemImage: "eye.slash", title: L("blind.empty.title"), message: L("blind.empty.message"))
        } else {
            if subjectID == nil {
                Picker(L("common.subject"), selection: Binding(get: { subjectIDResolved }, set: { selectedSubject = $0 })) {
                    ForEach(store.db.subjects) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Chip(text: L("blind.cue"), systemImage: "eye.slash")
                    Text(store.subject(subjectIDResolved)?.name ?? "").font(.memoraTitle)
                    Text(LF("blind.instructions", topicItems.count)).font(.callout).foregroundStyle(.secondary)
                }
            }
            AnswerEditor(text: $text, placeholder: L("blind.placeholder"), minHeight: 260)
            ConfidencePicker(selection: $confidence)
            Button(L("blind.check")) { evaluate() }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .disabled(TextNormalizer.isBlank(text) || topicItems.isEmpty || (store.settings.requireConfidence && confidence == nil))
        }
    }

    @ViewBuilder
    private var resultsView: some View {
        let recalled = results.filter { $0.evaluation.outcome == .correct }.count
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(LF("blind.score", recalled, results.count)).font(.memoraTitle)
                ProgressBar(value: results.isEmpty ? 0 : Double(recalled) / Double(results.count), tint: Theme.success)
                Text(L("blind.note")).font(.caption).foregroundStyle(.secondary)
            }
        }
        ForEach(results, id: \.item.id) { row in
            GlassCard(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.item.title).font(.headline)
                        Spacer()
                        Chip(text: row.evaluation.outcome.title, tint: Theme.color(for: row.evaluation.outcome))
                    }
                    if row.evaluation.outcome != .correct {
                        Text(row.item.answer).font(.callout).foregroundStyle(.secondary)
                        BulletList(title: L("study.missingPoints"), items: row.evaluation.missingPoints, systemImage: "circle.dashed", tint: Theme.warning)
                    }
                }
            }
        }
        if phase == .results {
            Button(L("blind.save")) { save() }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
        } else {
            Button(L("common.done")) { dismiss() }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
        }
    }

    private func evaluate() {
        UIApplication.shared.dismissKeyboard()
        results = topicItems.map { item -> (item: LearningItem, evaluation: AnswerEvaluation) in
            let coverage = AnswerEvaluator.coverage(of: text, keyPoints: item.gradingPoints, expected: item.answer)
            let outcome: Outcome = coverage.score >= AnswerEvaluator.correctThreshold ? .correct
                : coverage.score >= AnswerEvaluator.partialThreshold ? .partial : .noAnswer
            let evaluation = AnswerEvaluation(outcome: outcome, score: coverage.score, matchedPoints: coverage.matched,
                                              missingPoints: coverage.missing,
                                              feedback: AnswerEvaluator.feedback(for: outcome, missing: coverage.missing))
            return (item: item, evaluation: evaluation)
        }.sorted { $0.evaluation.score > $1.evaluation.score }
        phase = .results
        Haptics.success()
    }

    private func save() {
        var summary = SessionSummary()
        let seconds = Date().timeIntervalSince(startedAt) / Double(max(1, results.count))
        for row in results {
            let input = AttemptInput(exerciseType: .blindRecall, evaluation: row.evaluation, confidence: confidence, hintsUsed: 0,
                                     responseSeconds: seconds, userAnswer: text, mode: .blindRecall, sessionID: sessionID,
                                     variantIndex: nil, overrideRating: nil, countsForScheduling: true, date: Date())
            let result = ReviewProcessor.process(item: row.item, input: input, context: ClassificationContext(), scheduler: store.scheduler)
            store.apply(result)
            summary.record(result, confidence: confidence)
        }
        store.recordSession(StudySessionRecord(id: sessionID, mode: .blindRecall, subjectID: subjectIDResolved, startedAt: startedAt,
                                               endedAt: Date(), attempts: summary.attempts, correct: summary.correct,
                                               partial: summary.partial, incorrect: summary.incorrect))
        store.saveNow()
        phase = .saved
        Task { await ReminderService.shared.refresh(store: store) }
    }
}
