import Foundation
import SwiftUI

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case arabic = "ar"
    case english = "en"
    var id: String { rawValue }
    var displayName: String { self == .arabic ? "العربية" : "English" }
    var layoutDirection: LayoutDirection { self == .arabic ? .rightToLeft : .leftToRight }
    /// Arabic UI with Latin digits (0123), as preferred for the app and widgets.
    var locale: Locale { self == .arabic ? Locale(identifier: "ar@numbers=latn") : Locale(identifier: "en_US") }
    var speechLocaleIdentifier: String { self == .arabic ? "ar-SA" : "en-US" }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var title: String { L("appearance.\(rawValue)") }
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

enum ReminderFrequency: String, Codable, CaseIterable, Identifiable {
    case low, normal, high
    var id: String { rawValue }
    var title: String { L("freq.\(rawValue)") }
    var maxPerDay: Int {
        switch self {
        case .low: return 1
        case .normal: return 2
        case .high: return 3
        }
    }
}

struct ReminderSettings: Codable, Equatable {
    var enabled: Bool = true
    var dailyMinuteOfDay: Int = 19 * 60
    var overdueAlerts: Bool = true
    var weakAlerts: Bool = true
    var frequency: ReminderFrequency = .normal
    var quietHoursEnabled: Bool = true
    var quietStartMinute: Int = 22 * 60
    var quietEndMinute: Int = 8 * 60
    var minimumDueCount: Int = 3
}

/// Optional sleep schedule. Used only to place workload and reminders;
/// the app never measures sleep or memory consolidation.
struct SleepSettings: Codable, Equatable {
    var enabled: Bool = false
    var bedtimeMinute: Int = 23 * 60
    var wakeMinute: Int = 7 * 60
    var preSleepReview: Bool = true
    var morningRetrieval: Bool = true
}

struct AppSettings: Codable, Equatable {
    var language: AppLanguage = .arabic
    var appearance: AppearanceMode = .dark
    var fsrs: FSRSParameters = FSRSParameters()
    var dailyNewLimit: Int = 10
    var sessionSize: Int = 20
    var interleaving: Bool = true
    var requireConfidence: Bool = true
    var pretestNewTopics: Bool = true
    var generationPrompts: Bool = true
    var useAIEvaluation: Bool = true
    var aiModel: String = "gemini-flash-latest"
    var hapticsEnabled: Bool = true
    var reminders: ReminderSettings = ReminderSettings()
    var sleep: SleepSettings = SleepSettings()
}

// Tolerant decoding: new settings added in later versions fall back to defaults
// instead of failing the whole database load. Declared in extensions so the
// implicit memberwise/default initializers are preserved.

extension KeyedDecodingContainer {
    func decode<T: Decodable>(_ key: Key, default value: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? value
    }
}

extension ReminderSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReminderSettings()
        self = d
        enabled = c.decode(.enabled, default: d.enabled)
        dailyMinuteOfDay = c.decode(.dailyMinuteOfDay, default: d.dailyMinuteOfDay)
        overdueAlerts = c.decode(.overdueAlerts, default: d.overdueAlerts)
        weakAlerts = c.decode(.weakAlerts, default: d.weakAlerts)
        frequency = c.decode(.frequency, default: d.frequency)
        quietHoursEnabled = c.decode(.quietHoursEnabled, default: d.quietHoursEnabled)
        quietStartMinute = c.decode(.quietStartMinute, default: d.quietStartMinute)
        quietEndMinute = c.decode(.quietEndMinute, default: d.quietEndMinute)
        minimumDueCount = c.decode(.minimumDueCount, default: d.minimumDueCount)
    }
}

extension SleepSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SleepSettings()
        self = d
        enabled = c.decode(.enabled, default: d.enabled)
        bedtimeMinute = c.decode(.bedtimeMinute, default: d.bedtimeMinute)
        wakeMinute = c.decode(.wakeMinute, default: d.wakeMinute)
        preSleepReview = c.decode(.preSleepReview, default: d.preSleepReview)
        morningRetrieval = c.decode(.morningRetrieval, default: d.morningRetrieval)
    }
}

extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        self = d
        language = c.decode(.language, default: d.language)
        appearance = c.decode(.appearance, default: d.appearance)
        fsrs = c.decode(.fsrs, default: d.fsrs)
        dailyNewLimit = c.decode(.dailyNewLimit, default: d.dailyNewLimit)
        sessionSize = c.decode(.sessionSize, default: d.sessionSize)
        interleaving = c.decode(.interleaving, default: d.interleaving)
        requireConfidence = c.decode(.requireConfidence, default: d.requireConfidence)
        pretestNewTopics = c.decode(.pretestNewTopics, default: d.pretestNewTopics)
        generationPrompts = c.decode(.generationPrompts, default: d.generationPrompts)
        useAIEvaluation = c.decode(.useAIEvaluation, default: d.useAIEvaluation)
        aiModel = c.decode(.aiModel, default: d.aiModel)
        hapticsEnabled = c.decode(.hapticsEnabled, default: d.hapticsEnabled)
        reminders = c.decode(.reminders, default: d.reminders)
        sleep = c.decode(.sleep, default: d.sleep)
    }
}
