import Foundation

/// Plans content reminders: at each card's spaced due time, a notification shows the
/// card's cue (never the answer) so the learner tries to recall it — retrieval practice
/// delivered on the spacing schedule. Cards due close together share one notification.
enum ItemReminderPlanner {
    static let identifierPrefix = "memora.item."
    static let maxNotifications = 36
    static let maxCardsPerNotification = 3
    static let mergeWindow: TimeInterval = 30 * 60
    static let horizon: TimeInterval = 45 * 86_400

    struct Card: Equatable {
        var id: UUID
        var due: Date
        var cue: String
        var subject: String
    }

    struct Planned: Equatable {
        var identifier: String
        var fireDate: Date
        var cards: [Card]
    }

    static func plan(now: Date, cards: [Card], quietStart: Int?, quietEnd: Int?, calendar: Calendar = .current) -> [Planned] {
        let upcoming = cards
            .filter { $0.due > now.addingTimeInterval(5 * 60) && $0.due < now.addingTimeInterval(horizon) }
            .sorted { $0.due < $1.due }
        var result: [Planned] = []
        for card in upcoming {
            let fire = outsideQuietHours(card.due, start: quietStart, end: quietEnd, calendar: calendar)
            if var last = result.last, fire.timeIntervalSince(last.fireDate) < mergeWindow, last.cards.count < maxCardsPerNotification {
                last.cards.append(card)
                result[result.count - 1] = last
                continue
            }
            guard result.count < maxNotifications else { break }
            result.append(Planned(identifier: identifierPrefix + card.id.uuidString, fireDate: fire, cards: [card]))
        }
        return result
    }

    /// Moves a time inside quiet hours to the end of them (same or next morning).
    static func outsideQuietHours(_ date: Date, start: Int?, end: Int?, calendar: Calendar) -> Date {
        guard let start, let end, start != end else { return date }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let inQuiet = start > end ? (minute >= start || minute < end) : (minute >= start && minute < end)
        guard inQuiet else { return date }
        var day = calendar.startOfDay(for: date)
        if start > end && minute >= start { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day }
        return day.addingTimeInterval(TimeInterval(end * 60))
    }
}
