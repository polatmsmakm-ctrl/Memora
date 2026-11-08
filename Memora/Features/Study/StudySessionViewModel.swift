import Foundation
import SwiftUI
import UIKit

struct SessionSummary {
    var attempts = 0
    var correct = 0
    var partial = 0
    var incorrect = 0
    var restudied = 0
    var followUps = 0
    var errors: [ErrorCategory: Int] = [:]
    var confidenceSum = 0.0
    var confidenceCount = 0
    var itemIDs: Set<UUID> = []

    mutating func record(_ result: AttemptResult, confidence: ConfidenceLevel?) {
        attempts += 1
        itemIDs.insert(result.item.id)
        switch result.log.outcome {
        case .correct: correct += 1
        case .partial: partial += 1
        case .incorrect, .noAnswer: incorrect += 1
        }
        if let category = result.errorCategory { errors[category, default: 0] += 1 }
        if let confidence {
            confidenceSum += confidence.probability
            confidenceCount += 1
        }
    }

    var accuracy: Double? { attempts == 0 ? nil : Double(correct) / Double(attempts) }
    var meanConfidence: Double? { confidenceCount == 0 ? nil : confidenceSum / Double(confidenceCount) }
}

/// Runs a retrieval session: attempt → confidence → evaluation → error type →
/// intervention → FSRS update → follow-up retrieval later in the same session.
@MainActor
final class StudySessionViewModel: ObservableObject {
    enum Phase: Equatable { case answering, evaluating, feedback, finished, empty }

    let request: SessionRequest
    let store: MemoraStore

    @Published private(set) var queue: [Exercise] = []
    @Published private(set) var index = 0
    @Published private(set) var phase: Phase = .answering
    @Published var answerText = ""
    @Published var selectedChoice: Int?
    @Published var confidence: ConfidenceLevel?
    @Published private(set) var revealedHints: [String] = []
    @Published private(set) var evaluation: AnswerEvaluation?
    @Published private(set) var category: ErrorCategory?
    @Published private(set) var intervention: Intervention?
    @Published private(set) var suggestedRating: Rating = .good
    @Published var chosenRating: Rating = .good
    @Published private(set) var ratingPreview: [Rating: TimeInterval] = [:]
    @Published private(set) var aiNotice: String?
    @Published var showConfidenceRequired = false
    @Published private(set) var summary = SessionSummary()

    private let sessionID = UUID()
    private let startedAt = Date()
    private var exerciseStartedAt = Date()
    private var responseSeconds: Double = 0
    private var context = ClassificationContext()
    private var rng: SeededGenerator
    private var followUpCounts: [UUID: Int] = [:]
    private var experimentResults: [ExperimentTestResult] = []
    private var evaluationTask: Task<Void, Never>?

    init(request: SessionRequest, store: MemoraStore) {
        self.request = request
        self.store = store
        var generator = SeededGenerator(date: Date())
        let builder = SessionBuilder(scheduler: store.scheduler, settings: store.settings, now: Date())
        let excluded = request.mode == .experiment ? Set<UUID>() : store.experimentLockedItemIDs
        let built = builder.buildExercises(for: request, in: store.db, excluded: excluded, rng: &generator)
        self.rng = generator
        self.queue = built
        self.phase = built.isEmpty ? .empty : .answering
    }

    // MARK: State

    var current: Exercise? { queue.indices.contains(index) ? queue[index] : nil }
    var currentItem: LearningItem? { current.flatMap { store.item($0.itemID) } }
    var progress: Double { queue.isEmpty ? 0 : Double(min(index, queue.count)) / Double(queue.count) }
    var needsConfidence: Bool { store.settings.requireConfidence && current?.type != .restudy }
    var allHints: [String] { current.map { HintGenerator.hints(for: $0, item: currentItem) } ?? [] }
    var canRevealHint: Bool { request.mode != .exam && revealedHints.count < allHints.count }
    var canSubmit: Bool {
        guard let current else { return false }
        if current.type == .multipleChoice { return selectedChoice != nil }
        if current.type == .restudy { return true }
        return !TextNormalizer.isBlank(answerText)
    }
    var showsRatingControls: Bool { request.countsForScheduling }

    // MARK: Actions

    func revealHint() {
        let hints = allHints
        guard revealedHints.count < hints.count else { return }
        revealedHints.append(hints[revealedHints.count])
        Haptics.tap()
    }

    func submit() {
        guard phase == .answering, let exercise = current else { return }
        if exercise.type == .restudy {
            summary.restudied += 1
            advance()
            return
        }
        if needsConfidence && confidence == nil {
            showConfidenceRequired = true
            Haptics.warning()
            return
        }
        responseSeconds = Date().timeIntervalSince(exerciseStartedAt)
        UIApplication.shared.dismissKeyboard()

        if exercise.type == .multipleChoice {
            finish(with: AnswerEvaluator.evaluateChoice(selected: selectedChoice, exercise: exercise))
            return
        }
        let local = AnswerEvaluator.evaluate(answer: answerText, exercise: exercise)
        let wantsAI = store.settings.useAIEvaluation && AIService.isAvailable && local.outcome != .noAnswer
            && (exercise.type.benefitsFromAI || local.outcome == .partial)
        guard wantsAI, let item = currentItem else {
            finish(with: local)
            return
        }
        phase = .evaluating
        let service = AIService.make(settings: store.settings)
        let answer = answerText
        evaluationTask = Task { [weak self] in
            do {
                let result = try await service.evaluate(answer: answer, exercise: exercise, item: item)
                self?.finish(with: result)
            } catch {
                self?.aiNotice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self?.finish(with: local)
            }
        }
    }

    func dontKnow() {
        guard phase == .answering, let exercise = current else { return }
        responseSeconds = Date().timeIntervalSince(exerciseStartedAt)
        answerText = ""
        selectedChoice = nil
        if confidence == nil { confidence = .guess }
        UIApplication.shared.dismissKeyboard()
        finish(with: AnswerEvaluation(outcome: .noAnswer, score: 0, missingPoints: exercise.keyPoints, feedback: L("feedback.noAnswer")))
    }

    /// Learner disagrees with the automatic grading.
    func selfGrade(_ outcome: Outcome) {
        guard let evaluation else { return }
        self.evaluation = AnswerEvaluator.selfGraded(evaluation, outcome: outcome)
        recomputeDecision()
        Haptics.selection()
    }

    func continueToNext() {
        guard phase == .feedback, let exercise = current, let item = currentItem, let evaluation else {
            advance()
            return
        }
        let chosenText: String
        if exercise.type == .multipleChoice, let choice = selectedChoice, exercise.choices.indices.contains(choice) {
            chosenText = exercise.choices[choice]
        } else {
            chosenText = answerText
        }
        let input = AttemptInput(exerciseType: exercise.type,
                                 evaluation: evaluation,
                                 confidence: confidence,
                                 hintsUsed: revealedHints.count,
                                 responseSeconds: responseSeconds,
                                 userAnswer: chosenText,
                                 mode: request.mode,
                                 sessionID: sessionID,
                                 variantIndex: exercise.variantIndex,
                                 overrideRating: chosenRating,
                                 countsForScheduling: request.countsForScheduling,
                                 date: Date())
        let result = ReviewProcessor.process(item: item, input: input, context: context, scheduler: store.scheduler)
        store.apply(result)
        summary.record(result, confidence: confidence)

        if request.mode == .pretest {
            store.addPretest(PretestRecord(itemID: item.id, date: Date(), phase: .pre, score: evaluation.score, outcome: evaluation.outcome))
        }
        if request.mode == .experiment, request.experimentPhase == .test,
           let note = exercise.contextNote, let condition = ExperimentCondition(rawValue: note) {
            experimentResults.append(ExperimentTestResult(itemID: item.id, condition: condition, outcome: evaluation.outcome,
                                                          score: evaluation.score, date: Date()))
        }
        scheduleFollowUps(after: result)
        advance()
    }

    func endSession() {
        evaluationTask?.cancel()
        finishSession()
    }

    // MARK: Internals

    private func finish(with evaluation: AnswerEvaluation) {
        guard let exercise = current, let item = currentItem else { return }
        self.evaluation = evaluation
        context = store.classificationContext(for: item, answer: answerText, exerciseType: exercise.type)
        recomputeDecision()
        ratingPreview = request.countsForScheduling ? store.scheduler.preview(item.card, at: Date()) : [:]
        phase = .feedback
        Haptics.outcome(evaluation.outcome)
    }

    private func recomputeDecision() {
        guard let evaluation, let exercise = current, let item = currentItem else { return }
        category = ErrorClassifier.classify(evaluation: evaluation,
                                            confidence: confidence,
                                            exerciseType: exercise.type,
                                            hintsUsed: revealedHints.count,
                                            priorFailures: item.profile.failureCount,
                                            context: context)
        intervention = category.map { InterventionPlanner.plan(for: $0, evaluation: evaluation, context: context) }
        suggestedRating = RatingPolicy.suggestedRating(evaluation: evaluation,
                                                       confidence: confidence,
                                                       hintsUsed: revealedHints.count,
                                                       exerciseType: exercise.type,
                                                       responseSeconds: responseSeconds)
        chosenRating = suggestedRating
    }

    /// Another retrieval opportunity, spaced a few exercises later, shaped by the error type.
    private func scheduleFollowUps(after result: AttemptResult) {
        guard request.countsForScheduling, request.mode != .experiment, request.mode != .exam else { return }
        let item = result.item
        let maxFollowUps = request.mode == .successiveRelearning ? 3 : 2
        let count = followUpCounts[item.id] ?? 0
        guard count < maxFollowUps else { return }
        var additions: [Exercise] = []
        let upcoming = queue.indices.contains(index + 1) ? Array(queue[(index + 1)...]) : []

        if let intervention = result.intervention {
            if intervention.kind == .reviewPrerequisites {
                for prerequisite in store.weakPrerequisites(of: item).prefix(2) where !upcoming.contains(where: { $0.itemID == prerequisite.id }) {
                    let type: ExerciseType = prerequisite.isIntroduced ? .shortAnswer : .restudy
                    additions.append(ExerciseFactory.make(type, for: prerequisite, siblings: store.siblings(of: prerequisite), rng: &rng, isFollowUp: true))
                }
                additions.append(ExerciseFactory.make(.shortAnswer, for: item, siblings: store.siblings(of: item), rng: &rng, isFollowUp: true))
            } else if let type = intervention.followUpType {
                let comparison = intervention.comparisonTitle.flatMap { title in
                    store.db.items.first { $0.title == title && $0.id != item.id }
                }
                additions.append(ExerciseFactory.make(type, for: item, siblings: store.siblings(of: item), comparison: comparison,
                                                      focusPoints: intervention.focusPoints, rng: &rng, isFollowUp: true))
            }
        } else if request.mode == .successiveRelearning && !result.log.outcome.isSuccess {
            additions.append(ExerciseFactory.make(.shortAnswer, for: item, siblings: store.siblings(of: item), rng: &rng, isFollowUp: true))
        }
        guard !additions.isEmpty else { return }
        followUpCounts[item.id] = count + 1
        let insertAt = min(index + 1 + 3, queue.count)
        queue.insert(contentsOf: additions, at: insertAt)
        summary.followUps += additions.count
    }

    private func advance() {
        index += 1
        resetInput()
        if index >= queue.count { finishSession() }
    }

    private func resetInput() {
        answerText = ""
        selectedChoice = nil
        confidence = nil
        revealedHints = []
        evaluation = nil
        category = nil
        intervention = nil
        aiNotice = nil
        ratingPreview = [:]
        showConfidenceRequired = false
        exerciseStartedAt = Date()
        phase = .answering
    }

    private func finishSession() {
        guard phase != .finished, phase != .empty else { return }
        phase = .finished
        let record = StudySessionRecord(id: sessionID, mode: request.mode, subjectID: request.subjectID,
                                        startedAt: startedAt, endedAt: Date(), attempts: summary.attempts,
                                        correct: summary.correct, partial: summary.partial, incorrect: summary.incorrect)
        store.recordSession(record)
        if request.mode == .experiment, let id = request.experimentID {
            if request.experimentPhase == .test {
                store.recordExperimentResults(id, results: experimentResults)
            } else if let condition = request.experimentCondition, summary.attempts + summary.restudied > 0 {
                store.recordExperimentPractice(id, condition: condition)
            }
        }
        store.saveNow()
        Haptics.success()
        Task { await ReminderService.shared.refresh(store: store) }
    }
}
