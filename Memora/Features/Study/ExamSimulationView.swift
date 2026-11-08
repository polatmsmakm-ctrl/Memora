import SwiftUI

/// Timed exam with mixed formats and no feedback until the end (as in a real exam).
struct ExamSimulationView: View {
    let request: SessionRequest
    @EnvironmentObject private var store: MemoraStore
    @Environment(\.dismiss) private var dismiss

    enum Phase { case setup, running, grading, results }

    @State private var phase: Phase = .setup
    @State private var questionCount = 15
    @State private var minutes = 20
    @State private var subjectID: UUID?
    @State private var exercises: [Exercise] = []
    @State private var answers: [UUID: String] = [:]
    @State private var choices: [UUID: Int] = [:]
    @State private var index = 0
    @State private var startedAt = Date()
    @State private var deadline = Date()
    @State private var evaluations: [UUID: AnswerEvaluation] = [:]
    @State private var sessionID = UUID()
    @State private var summary = SessionSummary()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    switch phase {
                    case .setup: setupView
                    case .running: runningView
                    case .grading: ProgressView(L("exam.grading")).padding(.top, 80)
                    case .results: resultsView
                    }
                }
                .padding(Theme.padding)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .memoraScreen()
            .navigationTitle(StudyMode.exam.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(L("common.close"))
                }
                ToolbarItem(placement: .principal) {
                    if phase == .running {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = max(0, deadline.timeIntervalSince(context.date))
                            Text(String(format: "%02d:%02d", Int(remaining) / 60, Int(remaining) % 60))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(remaining < 60 ? Theme.danger : .primary)
                                .onChange(of: remaining <= 0) { _, expired in if expired { gradeAll() } }
                        }
                    }
                }
            }
            .keyboardDoneButton()
            .onAppear { subjectID = request.subjectID }
        }
    }

    private var setupView: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("exam.setup")).font(.memoraTitle)
                Text(L("exam.setup.body")).font(.callout).foregroundStyle(.secondary)
                Picker(L("common.subject"), selection: $subjectID) {
                    Text(L("common.allSubjects")).tag(UUID?.none)
                    ForEach(store.db.subjects) { Text($0.name).tag(Optional($0.id)) }
                }
                Stepper(LF("exam.questions", questionCount), value: $questionCount, in: 5...60, step: 5)
                Stepper(LF("exam.minutes", minutes), value: $minutes, in: 5...120, step: 5)
                Button(L("exam.start")) { start() }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(store.items(in: subjectID).filter(\.isIntroduced).isEmpty)
                if store.items(in: subjectID).filter(\.isIntroduced).isEmpty {
                    Text(L("exam.noItems")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var runningView: some View {
        if exercises.indices.contains(index) {
            let exercise = exercises[index]
            Text(LF("exam.progress", index + 1, exercises.count)).font(.caption).foregroundStyle(.secondary)
            ExercisePromptCard(exercise: exercise, item: nil, subjectName: nil)
            if exercise.type == .multipleChoice {
                ChoiceList(choices: exercise.choices, selection: Binding(get: { choices[exercise.id] }, set: { choices[exercise.id] = $0 }))
            } else {
                AnswerEditor(text: Binding(get: { answers[exercise.id] ?? "" }, set: { answers[exercise.id] = $0 }),
                             placeholder: L("study.placeholder.answer"))
            }
            HStack(spacing: 10) {
                Button(L("exam.previous")) { index -= 1 }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: .secondary))
                    .disabled(index == 0)
                if index + 1 < exercises.count {
                    Button(L("exam.next")) { index += 1 }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                } else {
                    Button(L("exam.finish")) { gradeAll() }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                }
            }
        }
    }

    @ViewBuilder
    private var resultsView: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("exam.results")).font(.memoraTitle)
                Text(Formatters.percent(score)).font(.memoraNumber)
                Text(LF("exam.resultsLine", summary.correct, summary.partial, summary.incorrect)).font(.callout).foregroundStyle(.secondary)
            }
        }
        ForEach(exercises) { exercise in
            if let evaluation = evaluations[exercise.id] {
                GlassCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(exercise.prompt).font(.subheadline.weight(.semibold))
                            Spacer()
                            Chip(text: evaluation.outcome.title, tint: Theme.color(for: evaluation.outcome))
                        }
                        Text(L("study.correctAnswer") + ": " + exercise.expectedAnswer).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        Button(L("common.done")) { dismiss() }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
    }

    private var score: Double {
        let values = evaluations.values.map(\.score)
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private func start() {
        var rng = SeededGenerator(date: Date())
        let builder = SessionBuilder(scheduler: store.scheduler, settings: store.settings, now: Date())
        var examRequest = request
        examRequest.subjectID = subjectID
        examRequest.limit = questionCount
        exercises = builder.buildExercises(for: examRequest, in: store.db, excluded: store.experimentLockedItemIDs, rng: &rng)
        guard !exercises.isEmpty else { return }
        startedAt = Date()
        deadline = Date().addingTimeInterval(Double(minutes) * 60)
        index = 0
        phase = .running
    }

    private func gradeAll() {
        guard phase == .running else { return }
        UIApplication.shared.dismissKeyboard()
        phase = .grading
        let perQuestion = Date().timeIntervalSince(startedAt) / Double(max(1, exercises.count))
        let useAI = store.settings.useAIEvaluation && AIService.isAvailable
        let service = AIService.make(settings: store.settings)
        Task { @MainActor in
            for exercise in exercises {
                guard let item = store.item(exercise.itemID) else { continue }
                var evaluation: AnswerEvaluation
                if exercise.type == .multipleChoice {
                    evaluation = AnswerEvaluator.evaluateChoice(selected: choices[exercise.id], exercise: exercise)
                } else {
                    let answer = answers[exercise.id] ?? ""
                    evaluation = AnswerEvaluator.evaluate(answer: answer, exercise: exercise)
                    if useAI && evaluation.outcome != .noAnswer && (exercise.type.benefitsFromAI || evaluation.outcome == .partial) {
                        if let ai = try? await service.evaluate(answer: answer, exercise: exercise, item: item) { evaluation = ai }
                    }
                }
                evaluations[exercise.id] = evaluation
                let answerText = exercise.type == .multipleChoice
                    ? (choices[exercise.id].flatMap { exercise.choices.indices.contains($0) ? exercise.choices[$0] : nil } ?? "")
                    : (answers[exercise.id] ?? "")
                let input = AttemptInput(exerciseType: exercise.type, evaluation: evaluation, confidence: nil, hintsUsed: 0,
                                         responseSeconds: perQuestion, userAnswer: answerText, mode: .exam, sessionID: sessionID,
                                         variantIndex: exercise.variantIndex, overrideRating: nil, countsForScheduling: true, date: Date())
                let context = store.classificationContext(for: item, answer: answerText, exerciseType: exercise.type)
                let result = ReviewProcessor.process(item: item, input: input, context: context, scheduler: store.scheduler)
                store.apply(result)
                summary.record(result, confidence: nil)
            }
            store.recordSession(StudySessionRecord(id: sessionID, mode: .exam, subjectID: subjectID, startedAt: startedAt, endedAt: Date(),
                                                   attempts: summary.attempts, correct: summary.correct, partial: summary.partial,
                                                   incorrect: summary.incorrect))
            store.saveNow()
            phase = .results
            Haptics.success()
            await ReminderService.shared.refresh(store: store)
        }
    }
}
