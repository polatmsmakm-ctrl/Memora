import SwiftUI

/// One clear screen for studying: review what's due, learn what's new.
struct TodayReviewView: View {
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter
    @State private var subjectID: UUID?

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
                        if store.db.subjects.count > 1 {
                            Picker(L("common.subject"), selection: $subjectID) {
                                Text(L("common.allSubjects")).tag(UUID?.none)
                                ForEach(store.db.subjects) { Text($0.name).tag(Optional($0.id)) }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        let due = dueItems
                        let fresh = newItems
                        if due.isEmpty && fresh.isEmpty {
                            GlassCard {
                                VStack(spacing: 10) {
                                    Text(L("today.done.title")).font(.title3.weight(.bold))
                                    Text(L("today.done.message")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                    Button(L("today.done.extra")) {
                                        router.start(SessionRequest(mode: .remember, subjectID: subjectID))
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                        } else {
                            actionCard(count: due.count, label: L("today.due"), button: L("today.due.go"),
                                       icon: "brain.head.profile", tint: Theme.accent) {
                                router.start(SessionRequest(mode: .smartReview, subjectID: subjectID))
                            }
                            actionCard(count: fresh.count, label: L("today.new"), button: L("today.new.go"),
                                       icon: "sparkles", tint: Theme.violet) {
                                router.start(SessionRequest(mode: .learn, subjectID: subjectID, itemIDs: Array(fresh.prefix(15).map(\.id))))
                            }
                        }
                        Button(L("today.moreModes")) { router.openAdvanced(.reviewModes) }
                            .font(.footnote)
                            .padding(.top, 4)
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

    private var dueItems: [LearningItem] {
        let now = Date()
        return store.items(in: subjectID).filter { $0.isIntroduced && !$0.isSuspended && store.scheduler.isDue($0.card, at: now) }
    }

    private var newItems: [LearningItem] {
        store.items(in: subjectID).filter { !$0.isIntroduced && !$0.isSuspended }
    }

    private func actionCard(count: Int, label: String, button: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: icon).foregroundStyle(tint)
                    Text(label).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(count)").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                }
                Button(action: action) { Text(button).frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(count == 0)
            }
        }
    }
}
