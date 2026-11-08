import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, learn, review, library, analytics, coach, settings
    var id: String { rawValue }
    var title: String { L("tab.\(rawValue)") }
    var icon: String {
        switch self {
        case .home: return "house"
        case .learn: return "book"
        case .review: return "brain.head.profile"
        case .library: return "books.vertical"
        case .analytics: return "chart.xyaxis.line"
        case .coach: return "sparkles"
        case .settings: return "gearshape"
        }
    }
    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .learn: return "book.fill"
        case .review: return "brain.head.profile"
        case .library: return "books.vertical.fill"
        case .analytics: return "chart.xyaxis.line"
        case .coach: return "sparkles"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Navigation state shared by the root view, notifications, widgets and deep links.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var selectedTab: AppTab = .home
    @Published var activeSession: SessionRequest?
    @Published var showImport = false
    @Published var importSubjectID: UUID?

    func start(_ request: SessionRequest) {
        Haptics.tap()
        activeSession = request
    }

    func openReview() {
        selectedTab = .review
        activeSession = SessionRequest(mode: .smartReview)
    }

    func openImport(subjectID: UUID? = nil) {
        importSubjectID = subjectID
        showImport = true
    }

    func handle(url: URL) {
        guard url.scheme == "memora" else { return }
        switch url.host {
        case "review": openReview()
        case "learn": selectedTab = .learn
        case "import": selectedTab = .library; openImport()
        case "analytics": selectedTab = .analytics
        default: selectedTab = .home
        }
    }

    func handleNotificationAction(_ identifier: String) {
        openReview()
    }
}
