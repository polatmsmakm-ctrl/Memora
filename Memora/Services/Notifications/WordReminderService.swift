import Foundation
import UserNotifications

/// Daily "today's words" notifications for vocabulary saved from a file in the coach.
/// Each day shows a few words with their meanings, cycling through the whole list.
/// Separate from the review reminders (which `ReminderService` rebuilds on every refresh).
enum WordReminderService {
    static let identifierPrefix = "words-memora."
    static let wordsPerDay = 4
    /// iOS keeps at most 64 pending notifications per app; leave room for review reminders.
    static let maxDays = 30

    struct Word { var front: String; var back: String }

    /// Schedules one notification per day at `minuteOfDay`, starting today (or tomorrow if
    /// that time has passed). Returns the number of days scheduled, or nil if not allowed.
    @discardableResult
    static func schedule(words: [Word], setTitle: String, minuteOfDay: Int) async -> Int? {
        guard !words.isEmpty else { return 0 }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        guard allowed else { return nil }

        // Replace earlier word reminders so lists don't pile up.
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) })

        let calendar = Calendar.current
        let now = Date()
        var start = calendar.startOfDay(for: now).addingTimeInterval(TimeInterval(minuteOfDay * 60))
        if start <= now.addingTimeInterval(60) { start = calendar.date(byAdding: .day, value: 1, to: start) ?? start }

        let groups = max(1, Int((Double(words.count) / Double(wordsPerDay)).rounded(.up)))
        let days = min(maxDays, max(groups, min(maxDays, groups * 3))) // repeat the list ~3 times
        for day in 0..<days {
            let index = (day % groups) * wordsPerDay
            let todays = words[index..<min(words.count, index + wordsPerDay)]
            let content = UNMutableNotificationContent()
            content.title = L("coach.words.notifTitle")
            content.subtitle = setTitle
            content.body = todays.map { "• \($0.front) — \($0.back)" }.joined(separator: "\n")
            content.sound = .default
            content.threadIdentifier = "memora.words"
            content.userInfo = ["route": "review"]
            guard let date = calendar.date(byAdding: .day, value: day, to: start) else { continue }
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let request = UNNotificationRequest(identifier: identifierPrefix + "\(day)",
                                                content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await center.add(request)
        }
        return days
    }
}
