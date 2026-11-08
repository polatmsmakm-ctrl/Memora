import Foundation

enum ReminderKind: String, Codable {
    case daily, overdue, weak, preSleep
    var priority: Int {
        switch self {
        case .daily: return 0
        case .overdue: return 1
        case .weak: return 2
        case .preSleep: return 3
        }
    }
}

struct ReminderCandidate: Equatable {
    var due: Date
    var isWeak: Bool
}

struct PlannedReminder: Equatable {
    var identifier: String
    var kind: ReminderKind
    var fireDate: Date
    var title: String
    var body: String
    var count: Int
}

/// Localised notification texts, injectable for tests.
struct ReminderTexts {
    var dailyTitle: String
    var dailyBody: (Int, Int) -> String
    var overdueTitle: String
    var overdueBody: (Int) -> String
    var weakTitle: String
    var weakBody: (Int) -> String
    var preSleepTitle: String
    var preSleepBody: (Int) -> String

    static var localized: ReminderTexts {
        ReminderTexts(dailyTitle: L("notif.daily.title"),
                      dailyBody: { count, minutes in LF("notif.daily.body", count, minutes) },
                      overdueTitle: L("notif.overdue.title"),
                      overdueBody: { LF("notif.overdue.body", $0) },
                      weakTitle: L("notif.weak.title"),
                      weakBody: { LF("notif.weak.body", $0) },
                      preSleepTitle: L("notif.presleep.title"),
                      preSleepBody: { LF("notif.presleep.body", $0) })
    }
}

/// Pure planning of local notifications from real review data. The service turns the
/// plan into `UNNotificationRequest`s. Kept separate so it can be unit-tested.
enum ReminderPlanner {
    static let identifierPrefix = "memora."

    static func plan(now: Date,
                     candidates: [ReminderCandidate],
                     reminders: ReminderSettings,
                     sleep: SleepSettings,
                     secondsPerReview: Double,
                     calendar: Calendar,
                     texts: ReminderTexts,
                     daysAhead: Int = 7) -> [PlannedReminder] {
        guard reminders.enabled, !candidates.isEmpty else { return [] }
        var planned: [PlannedReminder] = []
        let today = calendar.startOfDay(for: now)
        let minutes = { (count: Int) -> Int in max(1, Int((Double(count) * secondsPerReview / 60).rounded(.up))) }

        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let endOfDay = calendar.date(byAdding: .day, value: 1, to: day) else { continue }

            // Daily reminder: memories reaching their predicted forgetting point that day.
            if let fire = fireDate(day: day, minute: reminders.dailyMinuteOfDay, reminders: reminders, sleep: sleep, calendar: calendar), fire > now {
                let count = candidates.filter { $0.due < endOfDay }.count
                if count >= max(1, reminders.minimumDueCount) {
                    planned.append(PlannedReminder(identifier: identifierPrefix + "daily.\(offset)", kind: .daily, fireDate: fire,
                                                   title: texts.dailyTitle, body: texts.dailyBody(count, minutes(count)), count: count))
                }
            }

            // Pre-sleep review (optional, sleep-aware): a short look at today's material.
            if sleep.enabled && sleep.preSleepReview && reminders.frequency != .low {
                let minute = (sleep.bedtimeMinute - 60 + 1440) % 1440
                if let fire = fireDate(day: day, minute: minute, reminders: ReminderSettings(quietHoursEnabled: false), sleep: SleepSettings(), calendar: calendar), fire > now {
                    let count = candidates.filter { $0.due < endOfDay }.count
                    if count > 0 {
                        planned.append(PlannedReminder(identifier: identifierPrefix + "presleep.\(offset)", kind: .preSleep, fireDate: fire,
                                                       title: texts.preSleepTitle, body: texts.preSleepBody(min(count, 10)), count: count))
                    }
                }
            }
        }

        // Overdue: one nudge, a few hours from now (respecting quiet hours).
        if reminders.overdueAlerts {
            let overdue = candidates.filter { $0.due < today }.count
            if overdue > 0, let fire = adjustedForQuiet(now.addingTimeInterval(3 * 3600), reminders: reminders, sleep: sleep, calendar: calendar) {
                planned.append(PlannedReminder(identifier: identifierPrefix + "overdue", kind: .overdue, fireDate: fire,
                                               title: texts.overdueTitle, body: texts.overdueBody(overdue), count: overdue))
            }
        }

        // Weak memories: at most one alert, the next day two hours before the daily reminder.
        if reminders.weakAlerts {
            let weak = candidates.filter(\.isWeak).count
            if weak >= 3, let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
               let fire = fireDate(day: tomorrow, minute: (reminders.dailyMinuteOfDay - 120 + 1440) % 1440, reminders: reminders, sleep: sleep, calendar: calendar) {
                planned.append(PlannedReminder(identifier: identifierPrefix + "weak", kind: .weak, fireDate: fire,
                                               title: texts.weakTitle, body: texts.weakBody(weak), count: weak))
            }
        }

        return capped(planned, maxPerDay: reminders.frequency.maxPerDay, calendar: calendar)
    }

    /// Keeps the highest-priority reminders per calendar day.
    static func capped(_ reminders: [PlannedReminder], maxPerDay: Int, calendar: Calendar) -> [PlannedReminder] {
        let grouped = Dictionary(grouping: reminders) { calendar.startOfDay(for: $0.fireDate) }
        return grouped.values.flatMap { list in
            list.sorted { $0.kind.priority == $1.kind.priority ? $0.fireDate < $1.fireDate : $0.kind.priority < $1.kind.priority }
                .prefix(maxPerDay)
        }.sorted { $0.fireDate < $1.fireDate }
    }

    static func fireDate(day: Date, minute: Int, reminders: ReminderSettings, sleep: SleepSettings, calendar: Calendar) -> Date? {
        guard let date = calendar.date(byAdding: .minute, value: minute, to: day) else { return nil }
        return adjustedForQuiet(date, reminders: reminders, sleep: sleep, calendar: calendar)
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Quiet windows: the user's quiet hours plus (if enabled) bedtime → wake.
    static func quietWindows(reminders: ReminderSettings, sleep: SleepSettings) -> [(Int, Int)] {
        var windows: [(Int, Int)] = []
        if reminders.quietHoursEnabled { windows.append((reminders.quietStartMinute, reminders.quietEndMinute)) }
        if sleep.enabled { windows.append((sleep.bedtimeMinute, sleep.wakeMinute)) }
        return windows
    }

    static func isQuiet(minute: Int, reminders: ReminderSettings, sleep: SleepSettings) -> Bool {
        quietWindows(reminders: reminders, sleep: sleep).contains { start, end in
            if start == end { return false }
            return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
        }
    }

    /// Moves a date out of quiet hours to the end of the quiet window.
    static func adjustedForQuiet(_ date: Date, reminders: ReminderSettings, sleep: SleepSettings, calendar: Calendar) -> Date? {
        var candidate = date
        for _ in 0..<3 {
            let minute = minuteOfDay(candidate, calendar: calendar)
            guard isQuiet(minute: minute, reminders: reminders, sleep: sleep) else { return candidate }
            let ends = quietWindows(reminders: reminders, sleep: sleep).compactMap { start, end -> Int? in
                let inside = start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
                return inside ? end : nil
            }
            guard let end = ends.max() else { return candidate }
            var delta = end - minute
            if delta <= 0 { delta += 1440 }
            candidate = candidate.addingTimeInterval(Double(delta) * 60)
        }
        return isQuiet(minute: minuteOfDay(candidate, calendar: calendar), reminders: reminders, sleep: sleep) ? nil : candidate
    }
}
