import SwiftUI

/// Adaptive shell: a sidebar on iPad (regular width), a seven-item bottom bar on iPhone.
/// Opens straight into the main screen — no login or onboarding wall.
struct RootView: View {
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var keyboard = KeyboardObserver()

    var body: some View {
        Group {
            if sizeClass == .regular {
                splitLayout
            } else {
                compactLayout
            }
        }
        .fullScreenCover(item: $router.activeSession, onDismiss: { router.showPendingImport() }) { request in
            SessionContainerView(request: request)
                .environmentObject(store)
                .environmentObject(router)
                .environment(\.layoutDirection, store.settings.language.layoutDirection)
                .environment(\.locale, store.settings.language.locale)
                .preferredColorScheme(store.settings.appearance.colorScheme)
        }
        .sheet(isPresented: $router.showImport, onDismiss: { router.startPendingSession() }) {
            ImportView(initialSubjectID: router.importSubjectID)
                .environmentObject(store)
                .environmentObject(router)
                .environment(\.layoutDirection, store.settings.language.layoutDirection)
                .preferredColorScheme(store.settings.appearance.colorScheme)
        }
        .fullScreenCover(item: $router.memoReview) { request in
            MemoReviewView(itemIDs: request.itemIDs)
                .environmentObject(store)
                .environmentObject(router)
                .environment(\.layoutDirection, store.settings.language.layoutDirection)
                .environment(\.locale, store.settings.language.locale)
                .preferredColorScheme(store.settings.appearance.colorScheme)
        }
        .sheet(item: $router.advancedScreen, onDismiss: { router.advancedDidClose() }) { screen in
            AdvancedScreenView(screen: screen)
                .environmentObject(store)
                .environmentObject(router)
                .environment(\.layoutDirection, store.settings.language.layoutDirection)
                .environment(\.locale, store.settings.language.locale)
                .preferredColorScheme(store.settings.appearance.colorScheme)
        }
        .alert(L("common.error"), isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button(L("common.ok"), role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .overlay { GuideOverlay() }
        .task {
            // The guided tour described the old seven-tab layout, so it no longer starts
            // on its own; the simple layout explains itself.
            GuideCenter.shared.attach(store: store, router: router)
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            List(selection: Binding<AppTab?>(get: { router.selectedTab }, set: { if let tab = $0 { router.selectedTab = tab } })) {
                ForEach(AppTab.visibleTabs) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .guideAnchor(GuideAnchorID.tab(tab))
                        .tag(tab)
                }
            }
            .navigationTitle("Memora")
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        } detail: {
            tabRoot(router.selectedTab)
                .id(router.selectedTab)
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach(AppTab.visibleTabs) { tab in
                    tabRoot(tab)
                        .opacity(router.selectedTab == tab ? 1 : 0)
                        .allowsHitTesting(router.selectedTab == tab)
                        .accessibilityHidden(router.selectedTab != tab)
                }
            }
            if !keyboard.isVisible {
                CompactTabBar(selection: $router.selectedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: keyboard.isVisible)
    }

    @ViewBuilder
    private func tabRoot(_ tab: AppTab) -> some View {
        switch tab {
        case .add: AddView()
        case .home: HomeView()
        case .learn: LearnHubView()
        case .review: TodayReviewView()
        case .library: LibraryView()
        case .analytics: AnalyticsView()
        case .coach: CoachView()
        case .settings: SettingsView()
        }
    }
}

struct CompactTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.visibleTabs) { tab in
                Button {
                    if selection != tab { Haptics.selection() }
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(height: 22)
                        Text(tab.title)
                            .font(.system(size: 9.5, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(selection == tab ? Theme.accent : Color.secondary)
                    .contentShape(Rectangle())
                    .guideAnchor(GuideAnchorID.tab(tab))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }
}

/// One of the full app's extra screens, opened from Settings › Advanced tools.
struct AdvancedScreenView: View {
    var screen: AdvancedScreen
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        content
            .overlay(alignment: .bottom) {
                Button {
                    router.advancedScreen = nil
                } label: {
                    Label(L("common.close"), systemImage: "xmark")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, screen == .coach ? 70 : 12)
            }
            .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .home: HomeView()
        case .learn: LearnHubView()
        case .reviewModes: ReviewHubView()
        case .coach: CoachView()
        case .analytics: AnalyticsView()
        }
    }
}
