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
        .fullScreenCover(item: $router.activeSession) { request in
            SessionContainerView(request: request)
                .environmentObject(store)
                .environmentObject(router)
                .environment(\.layoutDirection, store.settings.language.layoutDirection)
                .environment(\.locale, store.settings.language.locale)
                .preferredColorScheme(store.settings.appearance.colorScheme)
        }
        .sheet(isPresented: $router.showImport) {
            ImportView(initialSubjectID: router.importSubjectID)
                .environmentObject(store)
                .environmentObject(router)
                .environment(\.layoutDirection, store.settings.language.layoutDirection)
                .preferredColorScheme(store.settings.appearance.colorScheme)
        }
        .alert(L("common.error"), isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button(L("common.ok"), role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            List(selection: Binding<AppTab?>(get: { router.selectedTab }, set: { if let tab = $0 { router.selectedTab = tab } })) {
                ForEach(AppTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon).tag(tab)
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
                ForEach(AppTab.allCases) { tab in
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
        case .home: HomeView()
        case .learn: LearnHubView()
        case .review: ReviewHubView()
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
            ForEach(AppTab.allCases) { tab in
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
