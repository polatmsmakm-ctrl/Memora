import SwiftUI

@main
struct MemoraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = MemoraStore()
    @StateObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
                .environment(\.layoutDirection, store.settings.language.layoutDirection)
                .environment(\.locale, store.settings.language.locale)
                .preferredColorScheme(store.settings.appearance.colorScheme)
                .tint(Theme.accent)
                .id(store.settings.language)
                .onOpenURL { router.handle(url: $0) }
                .task {
                    Haptics.enabled = store.settings.hapticsEnabled
                    ReminderService.shared.registerCategories()
                    await ReminderService.shared.refresh(store: store)
                }
                .onChange(of: store.settings.hapticsEnabled) { _, enabled in
                    Haptics.enabled = enabled
                }
                .onChange(of: store.settings.reminders) { _, _ in
                    Task { await ReminderService.shared.refresh(store: store) }
                }
                .onChange(of: store.settings.sleep) { _, _ in
                    Task { await ReminderService.shared.refresh(store: store) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                store.saveNow()
                Task { await ReminderService.shared.refresh(store: store) }
            case .active:
                Task { await ReminderService.shared.refreshAuthorization() }
            default:
                break
            }
        }
    }
}
