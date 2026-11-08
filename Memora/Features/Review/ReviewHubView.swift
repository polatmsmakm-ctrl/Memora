import SwiftUI

struct ReviewHubView: View {
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter
    @State private var subjectID: UUID?

    private let modes: [StudyMode] = [.smartReview, .remember, .quickDaily, .successiveRelearning, .blindRecall,
                                      .memoryRescue, .longTerm, .deepUnderstanding, .transfer, .exam]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if store.db.items.filter(\.isIntroduced).isEmpty {
                        EmptyStateView(systemImage: "brain.head.profile", title: L("review.empty.title"), message: L("review.empty.message"),
                                       actionTitle: L("review.empty.action")) { router.selectedTab = .learn }
                    } else {
                        Picker(L("common.subject"), selection: $subjectID) {
                            Text(L("common.allSubjects")).tag(UUID?.none)
                            ForEach(store.db.subjects) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
                            ForEach(modes) { mode in
                                ModeTile(mode: mode, badge: badge(for: mode)) {
                                    router.start(SessionRequest(mode: mode, subjectID: subjectID))
                                }
                            }
                        }
                        Text(L("review.footer")).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Theme.padding)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .memoraScreen()
            .navigationTitle(L("tab.review"))
        }
    }

    private func badge(for mode: StudyMode) -> String? {
        let items = store.items(in: subjectID).filter { $0.isIntroduced && !$0.isSuspended }
        switch mode {
        case .smartReview:
            let count = items.filter { store.scheduler.isDue($0.card, at: Date()) }.count
            return count > 0 ? "\(count)" : nil
        case .memoryRescue:
            let count = items.filter { $0.card.lapses >= 2 || $0.profile.failureCount >= 2 || store.memoryState(of: $0) == .weak }.count
            return count > 0 ? "\(count)" : nil
        case .successiveRelearning:
            let count = items.filter { $0.profile.distinctSuccessfulDays < MemoryStateClassifier.masterySessions }.count
            return count > 0 ? "\(count)" : nil
        case .transfer:
            let count = items.filter { !$0.transferProblems.isEmpty }.count
            return count > 0 ? "\(count)" : nil
        default:
            return nil
        }
    }
}
