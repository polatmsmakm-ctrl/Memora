import SwiftUI

struct StudySessionView: View {
    @StateObject private var vm: StudySessionViewModel
    @EnvironmentObject private var store: MemoraStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmExit = false

    init(request: SessionRequest, store: MemoraStore) {
        _vm = StateObject(wrappedValue: StudySessionViewModel(request: request, store: store))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        content
                    }
                    .padding(.horizontal, Theme.padding)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .id("top")
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: vm.index) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
                .onChange(of: vm.phase) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
            }
            .memoraScreen()
            .navigationTitle(vm.request.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if vm.phase == .finished || vm.phase == .empty || vm.summary.attempts == 0 {
                            dismiss()
                        } else {
                            confirmExit = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L("common.close"))
                }
                ToolbarItem(placement: .principal) {
                    if vm.phase != .finished && vm.phase != .empty {
                        VStack(spacing: 4) {
                            Text(vm.request.mode.title).font(.subheadline.weight(.semibold))
                            ProgressBar(value: vm.progress).frame(width: 140)
                        }
                    }
                }
            }
            .keyboardDoneButton()
            .confirmationDialog(L("study.exit.title"), isPresented: $confirmExit, titleVisibility: .visible) {
                Button(L("study.exit.save")) { vm.endSession(); dismiss() }
                Button(L("common.cancel"), role: .cancel) {}
            } message: {
                Text(L("study.exit.message"))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .empty:
            EmptyStateView(systemImage: "checkmark.circle", title: L("study.empty.title"), message: L("study.empty.message"),
                           actionTitle: L("common.close")) { dismiss() }
                .padding(.top, 60)
        case .finished:
            SessionSummaryView(summary: vm.summary, mode: vm.request.mode) { dismiss() }
        case .answering, .evaluating:
            answeringView
        case .feedback:
            FeedbackPanel(vm: vm)
            Button(L("study.continue")) { vm.continueToNext() }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
        }
    }

    @ViewBuilder
    private var answeringView: some View {
        if let exercise = vm.current {
            ExercisePromptCard(exercise: exercise, item: vm.currentItem, subjectName: store.subject(vm.currentItem?.subjectID)?.name)

            if exercise.type == .multipleChoice {
                ChoiceList(choices: exercise.choices, selection: $vm.selectedChoice)
            } else if exercise.type != .restudy {
                AnswerEditor(text: $vm.answerText, placeholder: placeholder(for: exercise.type),
                             minHeight: exercise.type == .freeRecall || exercise.type == .selfExplanation || exercise.type == .explanation ? 180 : 110)
            }

            HintsView(hints: vm.revealedHints)

            if vm.needsConfidence {
                ConfidencePicker(selection: $vm.confidence)
                    .padding(14)
                    .background(vm.showConfidenceRequired && vm.confidence == nil ? Theme.warning.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if vm.phase == .evaluating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L("study.evaluating")).font(.callout).foregroundStyle(.secondary)
                }
                .padding()
            } else {
                VStack(spacing: 10) {
                    Button(exercise.type == .restudy ? L("study.doneReading") : L("study.submit")) { vm.submit() }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        .disabled(!vm.canSubmit)
                    if exercise.type != .restudy {
                        HStack(spacing: 10) {
                            if vm.canRevealHint {
                                Button { vm.revealHint() } label: { Label(L("study.hint"), systemImage: "lightbulb") }
                                    .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: Theme.warning))
                            }
                            Button { vm.dontKnow() } label: { Label(L("study.dontKnow"), systemImage: "questionmark") }
                                .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: .secondary))
                        }
                    }
                }
            }
        }
    }

    private func placeholder(for type: ExerciseType) -> String {
        switch type {
        case .freeRecall, .blindRecall, .palace: return L("study.placeholder.recall")
        case .explanation, .selfExplanation, .elaboration, .comparison: return L("study.placeholder.explain")
        case .transferNear, .transferFar: return L("study.placeholder.apply")
        case .keyword: return L("study.placeholder.keywords")
        default: return L("study.placeholder.answer")
        }
    }
}

/// Routes a session request to the right experience.
struct SessionContainerView: View {
    let request: SessionRequest
    @EnvironmentObject private var store: MemoraStore

    var body: some View {
        switch request.mode {
        case .learn:
            LearnSessionView(request: request, store: store)
        case .blindRecall:
            BlindRecallView(subjectID: request.subjectID)
        case .exam:
            ExamSimulationView(request: request)
        default:
            StudySessionView(request: request, store: store)
        }
    }
}
