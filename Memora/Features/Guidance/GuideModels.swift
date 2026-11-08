import Foundation

/// Stable identifiers of interface elements that the tour can point at.
/// Elements report their on-screen frame with `.guideAnchor(_:)`; the tour never relies
/// on hard-coded screen positions.
enum GuideAnchorID: String, CaseIterable {
    case addMaterial
    case homeSummary
    case tabHome, tabLearn, tabReview, tabLibrary, tabAnalytics, tabCoach, tabSettings
    case settingsReminders

    static func tab(_ tab: AppTab) -> GuideAnchorID {
        switch tab {
        case .home: return .tabHome
        case .learn: return .tabLearn
        case .review: return .tabReview
        case .library: return .tabLibrary
        case .analytics: return .tabAnalytics
        case .coach: return .tabCoach
        case .settings: return .tabSettings
        }
    }
}

struct TourStep: Identifiable, Equatable {
    let id: String
    let anchor: GuideAnchorID
    /// Tab to show while this step is active.
    let tab: AppTab
    let systemImage: String

    var title: String { L("tour.\(id).title") }
    var message: String { L("tour.\(id).body") }
}

enum GuideTour {
    static let steps: [TourStep] = [
        TourStep(id: "add", anchor: .addMaterial, tab: .home, systemImage: "plus.circle"),
        TourStep(id: "summary", anchor: .homeSummary, tab: .home, systemImage: "sparkles"),
        TourStep(id: "learn", anchor: .tabLearn, tab: .learn, systemImage: "book"),
        TourStep(id: "review", anchor: .tabReview, tab: .review, systemImage: "brain.head.profile"),
        TourStep(id: "library", anchor: .tabLibrary, tab: .library, systemImage: "books.vertical"),
        TourStep(id: "analytics", anchor: .tabAnalytics, tab: .analytics, systemImage: "chart.xyaxis.line"),
        TourStep(id: "coach", anchor: .tabCoach, tab: .coach, systemImage: "sparkles"),
        TourStep(id: "reminders", anchor: .settingsReminders, tab: .settings, systemImage: "bell.badge")
    ]
}

/// One-time contextual explanations shown the first time a complex feature is opened.
/// Each is tracked independently by its raw value.
enum FeatureTip: String, CaseIterable, Identifiable {
    case studyConfidence, ratingSelector, knowledgeGraph, importReview, memoryPalace
    case experiments, blindRecall, priorKnowledge, memoryProfile, coachModes

    var id: String { rawValue }
    var title: String { L("tip.\(rawValue).title") }
    var message: String { L("tip.\(rawValue).body") }
    var systemImage: String {
        switch self {
        case .studyConfidence: return "gauge.with.dots.needle.50percent"
        case .ratingSelector: return "calendar.badge.clock"
        case .knowledgeGraph: return "point.3.connected.trianglepath.dotted"
        case .importReview: return "checkmark.shield"
        case .memoryPalace: return "building.columns"
        case .experiments: return "flask"
        case .blindRecall: return "eye.slash"
        case .priorKnowledge: return "map"
        case .memoryProfile: return "function"
        case .coachModes: return "bubble.left.and.text.bubble.right"
        }
    }
}
