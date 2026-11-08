import SwiftUI

/// The question side of an exercise. Never shows the expected answer
/// (except for restudy cards, which are explicitly reading tasks).
struct ExercisePromptCard: View {
    var exercise: Exercise
    var item: LearningItem?
    var subjectName: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Chip(text: exercise.type.title, systemImage: "rectangle.and.pencil.and.ellipsis")
                    if exercise.isFollowUp { Chip(text: L("study.followUp"), systemImage: "arrow.uturn.forward", tint: Theme.warning) }
                    Spacer()
                    if let subjectName { Text(subjectName).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                if exercise.type == .image, let image = ImageStore.load(exercise.imageFileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityLabel(L("study.image.a11y"))
                }
                Text(exercise.prompt)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if exercise.type == .restudy, let item {
                    Divider()
                    Text(item.answer).font(.body)
                    if !item.explanation.isEmpty {
                        Text(item.explanation).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct AnswerEditor: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 120

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: minHeight)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .accessibilityLabel(placeholder)
    }
}

struct ChoiceList: View {
    var choices: [String]
    @Binding var selection: Int?
    var revealCorrect: Int? = nil

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                Button {
                    guard revealCorrect == nil else { return }
                    selection = index
                    Haptics.selection()
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: index))
                            .foregroundStyle(tint(for: index))
                        Text(choice).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(tint(for: index).opacity(selection == index || revealCorrect == index ? 0.14 : 0.0),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
    }

    private func icon(for index: Int) -> String {
        if let correct = revealCorrect {
            if index == correct { return "checkmark.circle.fill" }
            if index == selection { return "xmark.circle.fill" }
        }
        return selection == index ? "largecircle.fill.circle" : "circle"
    }

    private func tint(for index: Int) -> Color {
        if let correct = revealCorrect {
            if index == correct { return Theme.success }
            if index == selection { return Theme.danger }
            return .secondary
        }
        return selection == index ? Theme.accent : .secondary
    }
}

struct HintsView: View {
    var hints: [String]

    var body: some View {
        if !hints.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(hints.enumerated()), id: \.offset) { index, hint in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb").foregroundStyle(Theme.warning)
                        Text(LF("study.hintN", index + 1) + " " + hint).font(.callout)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct BulletList: View {
    var title: String
    var items: [String]
    var systemImage: String
    var tint: Color

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(tint)
                        Text(item).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct RubricView: View {
    var rubric: RubricScores

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("study.rubric")).font(.subheadline.weight(.semibold))
            row(L("rubric.accuracy"), rubric.accuracy)
            row(L("rubric.completeness"), rubric.completeness)
            row(L("rubric.logic"), rubric.logic)
            row(L("rubric.depth"), rubric.depth)
        }
    }

    private func row(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 90, alignment: .leading)
            ProgressBar(value: value, tint: value >= 0.7 ? Theme.success : value >= 0.4 ? Theme.warning : Theme.danger)
            Text(Formatters.percent(value)).font(.caption.monospacedDigit()).frame(width: 44, alignment: .trailing)
        }
    }
}

/// FSRS rating picker showing the next interval each choice would produce.
struct RatingSelector: View {
    @Binding var selection: Rating
    var suggested: Rating
    var preview: [Rating: TimeInterval]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("study.rating.title")).font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(Rating.allCases) { rating in
                    Button {
                        selection = rating
                        Haptics.selection()
                    } label: {
                        VStack(spacing: 3) {
                            Text(rating.title).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            if let interval = preview[rating] {
                                Text(Formatters.interval(interval)).font(.caption2).monospacedDigit()
                            }
                            if rating == suggested {
                                Image(systemName: "sparkle").font(.system(size: 8))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(selection == rating ? Color.white : Color.primary)
                        .background(selection == rating ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == rating ? .isSelected : [])
                }
            }
            Text(L("study.rating.hint")).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Everything shown after an attempt: verdict, analysis, error type, intervention, rating.
struct FeedbackPanel: View {
    @ObservedObject var vm: StudySessionViewModel

    var body: some View {
        if let evaluation = vm.evaluation, let exercise = vm.current {
            VStack(alignment: .leading, spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: icon(evaluation.outcome))
                                .font(.title2)
                                .foregroundStyle(Theme.color(for: evaluation.outcome))
                            Text(evaluation.outcome.title).font(.title3.weight(.semibold))
                            Spacer()
                            if evaluation.source == .ai { Chip(text: L("study.gradedByAI"), systemImage: "sparkles", tint: Theme.violet) }
                            if evaluation.source == .selfGraded { Chip(text: L("study.selfGraded"), systemImage: "person") }
                        }
                        if !evaluation.feedback.isEmpty {
                            Text(evaluation.feedback).font(.callout)
                        }
                        if !vm.answerText.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L("study.yourAnswer")).font(.caption).foregroundStyle(.secondary)
                                Text(vm.answerText).font(.callout)
                            }
                        }
                        if exercise.type == .multipleChoice {
                            ChoiceList(choices: exercise.choices, selection: .constant(vm.selectedChoice), revealCorrect: exercise.correctChoiceIndex)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("study.correctAnswer")).font(.caption).foregroundStyle(.secondary)
                            Text(exercise.expectedAnswer).font(.body.weight(.medium)).textSelection(.enabled)
                        }
                        BulletList(title: L("study.correctPoints"), items: evaluation.matchedPoints, systemImage: "checkmark.circle", tint: Theme.success)
                        BulletList(title: L("study.missingPoints"), items: evaluation.missingPoints, systemImage: "circle.dashed", tint: Theme.warning)
                        BulletList(title: L("study.incorrectPoints"), items: evaluation.incorrectStatements, systemImage: "xmark.circle", tint: Theme.danger)
                        BulletList(title: L("study.misconceptions"), items: evaluation.misconceptions, systemImage: "exclamationmark.bubble", tint: Theme.danger)
                        if let rubric = evaluation.rubric { RubricView(rubric: rubric) }
                        if let notice = vm.aiNotice {
                            Label(notice, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if let category = vm.category {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(category.title, systemImage: category.systemImage).font(.headline).foregroundStyle(Theme.warning)
                            Text(category.detail).font(.callout).foregroundStyle(.secondary)
                            if let intervention = vm.intervention {
                                Divider()
                                Label(intervention.kind.title, systemImage: "arrow.triangle.turn.up.right.diamond")
                                    .font(.subheadline.weight(.semibold))
                                if let title = intervention.comparisonTitle {
                                    Text(LF("study.confusedWith", title)).font(.caption).foregroundStyle(.secondary)
                                }
                                if !intervention.prerequisiteTitles.isEmpty {
                                    Text(LF("study.weakPrereqs", intervention.prerequisiteTitles.joined(separator: "، "))).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let item = vm.currentItem, vm.intervention?.showExplanation == true || evaluation.outcome != .correct {
                    ReinforcementCard(item: item)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("study.selfGrade")).font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach([Outcome.correct, .partial, .incorrect], id: \.self) { outcome in
                                Button(outcome.title) { vm.selfGrade(outcome) }
                                    .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: Theme.color(for: outcome)))
                                    .font(.footnote)
                            }
                        }
                        if vm.showsRatingControls {
                            RatingSelector(selection: $vm.chosenRating, suggested: vm.suggestedRating, preview: vm.ratingPreview)
                                .featureTip(.ratingSelector, arrowEdge: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func icon(_ outcome: Outcome) -> String {
        switch outcome {
        case .correct: return "checkmark.seal.fill"
        case .partial: return "circle.lefthalf.filled"
        case .incorrect: return "xmark.octagon.fill"
        case .noAnswer: return "questionmark.circle.fill"
        }
    }
}

/// Re-encoding support shown after errors: explanation, example, mnemonic, image, source.
struct ReinforcementCard: View {
    var item: LearningItem
    @EnvironmentObject private var store: MemoraStore

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("study.reinforce"), systemImage: "book.pages").font(.headline)
                if let image = ImageStore.load(item.imageFileName) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !item.explanation.isEmpty { Text(item.explanation).font(.callout) }
                if let example = item.examples.first {
                    Text(L("item.example") + ": " + example).font(.callout).foregroundStyle(.secondary)
                }
                if let mnemonic = item.mnemonics.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mnemonic.kind.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.violet)
                        Text(mnemonic.content).font(.callout)
                    }
                }
                if let reference = item.sourceReference {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("item.source")).font(.caption).foregroundStyle(.secondary)
                        Text("“" + reference.quote + "”").font(.caption).italic()
                        if let source = store.source(reference.sourceID) {
                            Text(source.title + (reference.pageNumber.map { " · " + LF("item.page", $0) } ?? ""))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}
