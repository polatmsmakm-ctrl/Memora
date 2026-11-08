import SwiftUI
import UIKit

/// Learn mode: generate/predict → study (explanation, examples, visuals, mnemonic) →
/// immediate retrieval check (first FSRS review) → revisit pretest questions at the end.
@MainActor
final class LearnSessionViewModel: ObservableObject {
    enum Step: Equatable { case predict, study, check, feedback, posttest, finished, empty }

    let request: SessionRequest
    let store: MemoraStore

    @Published private(set) var items: [LearningItem] = []
    @Published private(set) var index = 0
    @Published private(set) var step: Step = .empty
    @Published var predictionText = ""
    @Published var answerText = ""
    @Published var confidence: ConfidenceLevel?
    @Published private(set) var evaluation: AnswerEvaluation?
    @Published private(set) var isEvaluating = false
    @Published private(set) var postItems: [LearningItem] = []
    @Published private(set) var postIndex = 0
    @Published var postAnswer = ""
    @Published private(set) var postEvaluation: AnswerEvaluation?
    @Published private(set) var summary = SessionSummary()

    private let sessionID = UUID()
    private let startedAt = Date()
    private var checkStartedAt = Date()
    private var rng = SeededGenerator(date: Date())
    private var checkExercise: Exercise?

    init(request: SessionRequest, store: MemoraStore) {
        self.request = request
        self.store = store
        var generator = SeededGenerator(date: Date())
        let builder = SessionBuilder(scheduler: store.scheduler, settings: store.settings, now: Date())
        let selected = builder.selectItems(for: request, in: store.db, excluded: store.experimentLockedItemIDs, rng: &generator)
            .filter { $0.card.state == .new }
        items = selected
        step = selected.first.map(initialStep(for:)) ?? .empty
    }

    var current: LearningItem? {
        guard items.indices.contains(index) else { return nil }
        return store.item(items[index].id) ?? items[index]
    }
    var exercise: Exercise? { checkExercise }
    var progress: Double { items.isEmpty ? 0 : Double(index) / Double(items.count) }

    private func initialStep(for item: LearningItem) -> Step {
        if item.priorKnowledge == .known { return .check }
        return store.settings.generationPrompts ? .predict : .study
    }

    func finishPrediction() {
        UIApplication.shared.dismissKeyboard()
        step = .study
        if let item = current { store.markIntroduced(item.id) }
    }

    func startCheck() {
        guard let item = current else { return }
        checkExercise = ExerciseFactory.make(.shortAnswer, for: item, siblings: store.siblings(of: item), rng: &rng)
        answerText = ""
        confidence = nil
        evaluation = nil
        checkStartedAt = Date()
        step = .check
    }

    func submitCheck(dontKnow: Bool = false) {
        if step != .check { startCheck() }
        guard let exercise = checkExercise, let item = current else { return }
        UIApplication.shared.dismissKeyboard()
        if dontKnow {
            answerText = ""
            if confidence == nil { confidence = .guess }
            show(AnswerEvaluation(outcome: .noAnswer, score: 0, missingPoints: exercise.keyPoints, feedback: L("feedback.noAnswer")))
            return
        }
        let local = AnswerEvaluator.evaluate(answer: answerText, exercise: exercise)
        guard store.settings.useAIEvaluation, AIService.isAvailable, local.outcome == .partial else {
            show(local)
            return
        }
        isEvaluating = true
        let service = AIService.make(settings: store.settings)
        let answer = answerText
        Task { [weak self] in
            let result = (try? await service.evaluate(answer: answer, exercise: exercise, item: item)) ?? local
            self?.isEvaluating = false
            self?.show(result)
        }
    }

    private func show(_ evaluation: AnswerEvaluation) {
        self.evaluation = evaluation
        step = .feedback
        Haptics.outcome(evaluation.outcome)
    }

    func selfGrade(_ outcome: Outcome) {
        guard let evaluation else { return }
        self.evaluation = AnswerEvaluator.selfGraded(evaluation, outcome: outcome)
    }

    func continueAfterFeedback() {
        guard let item = current, let exercise = checkExercise, let evaluation else { return }
        let input = AttemptInput(exerciseType: exercise.type, evaluation: evaluation, confidence: confidence, hintsUsed: 0,
                                 responseSeconds: Date().timeIntervalSince(checkStartedAt), userAnswer: answerText,
                                 mode: .learn, sessionID: sessionID, variantIndex: nil, overrideRating: nil,
                                 countsForScheduling: true, date: Date())
        let context = store.classificationContext(for: item, answer: answerText, exerciseType: exercise.type)
        let result = ReviewProcessor.process(item: item, input: input, context: context, scheduler: store.scheduler)
        store.apply(result)
        summary.record(result, confidence: confidence)
        nextItem()
    }

    /// A "known" item that failed the check gets studied before moving on.
    var shouldOfferStudy: Bool {
        guard let item = current, let evaluation else { return false }
        return item.priorKnowledge == .known && evaluation.outcome != .correct
    }

    func studyAfterFailedCheck() {
        continueAfterFeedbackKeepingItem()
    }

    private func continueAfterFeedbackKeepingItem() {
        guard let item = current, let exercise = checkExercise, let evaluation else { return }
        let input = AttemptInput(exerciseType: exercise.type, evaluation: evaluation, confidence: confidence, hintsUsed: 0,
                                 responseSeconds: Date().timeIntervalSince(checkStartedAt), userAnswer: answerText,
                                 mode: .learn, sessionID: sessionID, variantIndex: nil, overrideRating: nil,
                                 countsForScheduling: true, date: Date())
        let result = ReviewProcessor.process(item: item, input: input, context: ClassificationContext(), scheduler: store.scheduler)
        store.apply(result)
        summary.record(result, confidence: confidence)
        if let updated = store.item(item.id) { items[index] = updated }
        step = .study
    }

    private func nextItem() {
        index += 1
        predictionText = ""
        answerText = ""
        confidence = nil
        evaluation = nil
        checkExercise = nil
        if let next = current {
            step = initialStep(for: next)
        } else {
            beginPosttest()
        }
    }

    // MARK: Pretest revisit

    private func beginPosttest() {
        let ids = Set(items.map(\.id))
        postItems = store.db.items.filter { ids.contains($0.id) && $0.pretestedAt != nil }
        postIndex = 0
        if postItems.isEmpty { finish() } else { step = .posttest }
    }

    var currentPost: LearningItem? { postItems.indices.contains(postIndex) ? postItems[postIndex] : nil }

    func submitPost() {
        guard let item = currentPost else { return }
        UIApplication.shared.dismissKeyboard()
        let ex = Exercise(itemID: item.id, type: .shortAnswer, prompt: item.prompt, expectedAnswer: item.answer, keyPoints: item.gradingPoints)
        postEvaluation = AnswerEvaluator.evaluate(answer: postAnswer, exercise: ex)
    }

    func nextPost() {
        guard let item = currentPost, let evaluation = postEvaluation else { return }
        store.addPretest(PretestRecord(itemID: item.id, date: Date(), phase: .post, score: evaluation.score, outcome: evaluation.outcome))
        postIndex += 1
        postAnswer = ""
        postEvaluation = nil
        if currentPost == nil { finish() }
    }

    func finish() {
        guard step != .finished else { return }
        step = .finished
        store.recordSession(StudySessionRecord(id: sessionID, mode: .learn, subjectID: request.subjectID, startedAt: startedAt,
                                               endedAt: Date(), attempts: summary.attempts, correct: summary.correct,
                                               partial: summary.partial, incorrect: summary.incorrect))
        store.saveNow()
        Task { await ReminderService.shared.refresh(store: store) }
    }
}

struct LearnSessionView: View {
    @StateObject private var vm: LearnSessionViewModel
    @EnvironmentObject private var store: MemoraStore
    @Environment(\.dismiss) private var dismiss

    init(request: SessionRequest, store: MemoraStore) {
        _vm = StateObject(wrappedValue: LearnSessionViewModel(request: request, store: store))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) { content }
                    .padding(Theme.padding)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .memoraScreen()
            .navigationTitle(StudyMode.learn.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if vm.step != .finished && vm.step != .empty && vm.summary.attempts > 0 { vm.finish() }
                        dismiss()
                    } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(L("common.close"))
                }
                ToolbarItem(placement: .principal) {
                    if vm.step != .finished && vm.step != .empty {
                        ProgressBar(value: vm.progress).frame(width: 140)
                    }
                }
            }
            .keyboardDoneButton()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.step {
        case .empty:
            EmptyStateView(systemImage: "book.closed", title: L("learn.empty.title"), message: L("learn.empty.message"),
                           actionTitle: L("common.close")) { dismiss() }
                .padding(.top, 60)
        case .predict:
            if let item = vm.current { predictView(item) }
        case .study:
            if let item = vm.current { LearnStudyCard(item: item, prediction: vm.predictionText) { vm.startCheck() } }
        case .check:
            if let exercise = vm.exercise { checkView(exercise) }
        case .feedback:
            feedbackView
        case .posttest:
            posttestView
        case .finished:
            SessionSummaryView(summary: vm.summary, mode: .learn) { dismiss() }
        }
    }

    private func predictView(_ item: LearningItem) -> some View {
        VStack(spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Chip(text: L("learn.generate.chip"), systemImage: "wand.and.stars")
                    Text(item.prompt).font(.title3.weight(.semibold))
                    Text(L("learn.generate.body")).font(.callout).foregroundStyle(.secondary)
                }
            }
            AnswerEditor(text: $vm.predictionText, placeholder: L("learn.generate.placeholder"))
            Button(L("learn.generate.reveal")) { vm.finishPrediction() }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            Button(L("learn.generate.skip")) { vm.finishPrediction() }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: .secondary))
        }
    }

    private func checkView(_ exercise: Exercise) -> some View {
        VStack(spacing: 16) {
            ExercisePromptCard(exercise: exercise, item: nil, subjectName: nil)
            AnswerEditor(text: $vm.answerText, placeholder: L("study.placeholder.answer"))
            ConfidencePicker(selection: $vm.confidence)
            if vm.isEvaluating {
                ProgressView(L("study.evaluating"))
            } else {
                Button(L("study.submit")) { vm.submitCheck() }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(TextNormalizer.isBlank(vm.answerText) || (store.settings.requireConfidence && vm.confidence == nil))
                Button { vm.submitCheck(dontKnow: true) } label: { Label(L("study.dontKnow"), systemImage: "questionmark") }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: .secondary))
            }
        }
    }

    @ViewBuilder
    private var feedbackView: some View {
        if let evaluation = vm.evaluation, let exercise = vm.exercise {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label(evaluation.outcome.title, systemImage: evaluation.outcome == .correct ? "checkmark.seal.fill" : "arrow.triangle.2.circlepath")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.color(for: evaluation.outcome))
                    Text(evaluation.feedback).font(.callout)
                    Text(L("study.correctAnswer")).font(.caption).foregroundStyle(.secondary)
                    Text(exercise.expectedAnswer).font(.body.weight(.medium))
                    BulletList(title: L("study.missingPoints"), items: evaluation.missingPoints, systemImage: "circle.dashed", tint: Theme.warning)
                    HStack(spacing: 8) {
                        ForEach([Outcome.correct, .partial, .incorrect], id: \.self) { outcome in
                            Button(outcome.title) { vm.selfGrade(outcome) }
                                .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: Theme.color(for: outcome)))
                                .font(.footnote)
                        }
                    }
                    Text(L("learn.check.note")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if vm.shouldOfferStudy {
                Button(L("learn.studyNow")) { vm.studyAfterFailedCheck() }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            } else {
                Button(L("study.continue")) { vm.continueAfterFeedback() }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            }
        }
    }

    @ViewBuilder
    private var posttestView: some View {
        if let item = vm.currentPost {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Chip(text: L("learn.posttest.chip"), systemImage: "arrow.uturn.backward")
                    Text(item.prompt).font(.title3.weight(.semibold))
                    Text(L("learn.posttest.body")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let evaluation = vm.postEvaluation {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(evaluation.outcome.title).font(.headline).foregroundStyle(Theme.color(for: evaluation.outcome))
                        Text(item.answer).font(.callout)
                    }
                }
                Button(L("study.continue")) { vm.nextPost() }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
            } else {
                AnswerEditor(text: $vm.postAnswer, placeholder: L("study.placeholder.answer"))
                Button(L("study.submit")) { vm.submitPost() }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(TextNormalizer.isBlank(vm.postAnswer))
            }
        }
    }
}

/// Study card: verbal + visual encoding, examples, mnemonics and source reference.
struct LearnStudyCard: View {
    var item: LearningItem
    var prediction: String
    var onReady: () -> Void
    @EnvironmentObject private var store: MemoraStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Chip(text: item.kind.title)
                        OriginBadge(origin: item.origin)
                        Spacer()
                    }
                    Text(item.title).font(.memoraTitle)
                    if let image = ImageStore.load(item.imageFileName) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Text(item.answer).font(.body)
                    if !item.keyPoints.isEmpty {
                        FlowLayout {
                            ForEach(item.keyPoints, id: \.self) { Chip(text: $0, tint: Theme.violet) }
                        }
                    }
                    if !item.explanation.isEmpty {
                        Divider()
                        Text(item.explanation).font(.callout).foregroundStyle(.secondary)
                    }
                    if !prediction.isEmpty {
                        Divider()
                        Text(L("learn.yourPrediction")).font(.caption).foregroundStyle(.secondary)
                        Text(prediction).font(.callout).italic()
                    }
                }
            }
            if !item.examples.isEmpty || !item.analogies.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        BulletList(title: L("item.examples"), items: item.examples, systemImage: "list.bullet.rectangle", tint: Theme.accent)
                        BulletList(title: L("item.analogies"), items: item.analogies, systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", tint: Theme.violet)
                    }
                }
            }
            if !item.mnemonics.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L("item.mnemonics"), systemImage: "brain").font(.headline)
                        ForEach(item.mnemonics) { m in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.kind.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.violet)
                                Text(m.content).font(.callout)
                            }
                        }
                    }
                }
            }
            let prerequisites = PrerequisiteAnalyzer.prerequisiteIDs(of: item.id, links: store.db.links).compactMap { store.item($0) }
            if !prerequisites.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(L("item.prerequisites"), systemImage: "square.stack.3d.down.right").font(.headline)
                        ForEach(prerequisites) { p in
                            HStack {
                                Text(p.title).font(.callout)
                                Spacer()
                                MemoryStateBadge(state: store.memoryState(of: p))
                            }
                        }
                    }
                }
            }
            if let reference = item.sourceReference {
                Text("“" + reference.quote + "”").font(.caption).italic().foregroundStyle(.secondary)
            }
            Button(L("learn.ready"), action: onReady)
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
        }
    }
}
