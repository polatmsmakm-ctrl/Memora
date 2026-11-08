import Foundation

/// Runtime-switchable localisation. The UI language is an app setting (Arabic by
/// default, English optional) independent of the device language, so strings are
/// resolved from `StringsTable` rather than from the bundle's .lproj files.
/// Info.plist permission texts use the standard InfoPlist.strings files.
enum Localizer {
    static var language: AppLanguage = .arabic
}

/// Localised string for a key. Missing keys fall back to English, then to the key.
func L(_ key: String) -> String {
    StringsTable.lookup(key, language: Localizer.language)
}

/// Localised format string (uses `%@` for text and `%d` for integers, Latin digits).
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Locale(identifier: "en_US_POSIX"), arguments: args)
}

enum Formatters {
    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    static func number(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func date(_ date: Date, style: DateFormatter.Style = .medium, time: DateFormatter.Style = .none) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localizer.language.locale
        formatter.dateStyle = style
        formatter.timeStyle = time
        return formatter.string(from: date)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Localizer.language.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Human interval such as "10 min", "3 d", "2.5 mo".
    static func interval(_ seconds: TimeInterval) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return LF("unit.minutes", Int(minutes.rounded())) }
        let hours = minutes / 60
        if hours < 24 { return LF("unit.hours", Int(hours.rounded())) }
        let days = hours / 24
        if days < 31 { return LF("unit.days", Int(days.rounded())) }
        if days < 365 { return LF("unit.months", number(days / 30.4)) }
        return LF("unit.years", number(days / 365))
    }

    static func timeOfDay(minute: Int) -> String {
        String(format: "%02d:%02d", locale: Locale(identifier: "en_US_POSIX"), minute / 60, minute % 60)
    }
}
