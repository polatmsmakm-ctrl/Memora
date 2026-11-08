import Foundation
import UserNotifications

/// Schedules MEMORA's local notifications. Re-planned whenever the app goes to the
/// background, after every study session and when reminder settings change, so texts
/// always reflect current review data.
///
/// Platform notes: iOS keeps at most 64 pending local notifications per app (we plan
/// far fewer); notification text is fixed at scheduling time, so counts can be slightly
/// stale if the app is not opened for several days.
@MainActor
final class ReminderService: ObservableObject {
    static let shared = ReminderService()
    static let categoryIdentifier = "MEMORA_REVIEW"
    static let startReviewAction = "START_REVIEW"

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()

    func registerCategories() {
        let start = UNNotificationAction(identifier: Self.startReviewAction, title: L("notif.action.start"), options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.categoryIdentifier, actions: [start], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    func refresh(store: MemoraStore) async {
        await refreshAuthorization()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard store.settings.reminders.enabled else { return }
        guard authorization == .authorized || authorization == .provisional || authorization == .ephemeral else { return }

        let now = Date()
        let scheduler = store.scheduler
        let locked = store.experimentLockedItemIDs
        let candidates = store.db.items
            .filter { $0.isIntroduced && !$0.isSuspended && !locked.contains($0.id) }
            .map { ReminderCandidate(due: $0.card.due,
                                     isWeak: MemoryStateClassifier.state(of: $0, scheduler: scheduler, now: now) == .weak) }
        let plan = ReminderPlanner.plan(now: now,
                                        candidates: candidates,
                                        reminders: store.settings.reminders,
                                        sleep: store.settings.sleep,
                                        secondsPerReview: AnalyticsEngine.averageSecondsPerReview(logs: store.db.reviewLogs),
                                        calendar: .current,
                                        texts: .localized)
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.threadIdentifier = "memora"
            content.userInfo = ["route": "review", "kind": reminder.kind.rawValue]
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
