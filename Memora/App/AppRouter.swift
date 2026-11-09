import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case add, home, learn, review, library, analytics, coach, settings
    var id: String { rawValue }

    /// The simple layout shows only these; the others open from Settings › Advanced tools.
    static let visibleTabs: [AppTab] = [.add, .review, .library, .settings]
    var isVisible: Bool { Self.visibleTabs.contains(self) }
    var title: String { L("tab.\(rawValue)") }
    var icon: String {
        switch self {
        case .add: return "plus.circle"
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
        case .add: return "plus.circle.fill"
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

/// Extra screens from the full app, shown as a sheet from Settings › Advanced tools.
enum AdvancedScreen: String, Identifiable, CaseIterable {
    case home, learn, reviewModes, coach, analytics
    var id: String { rawValue }
    var title: String { L("advanced.\(rawValue)") }
    var icon: String {
        switch self {
        case .home: return "house"
        case .learn: return "book"
        case .reviewModes: return "square.grid.2x2"
        case .coach: return "sparkles"
        case .analytics: return "chart.xyaxis.line"
        }
    }
}

/// Navigation state shared by the root view, notifications, widgets and deep links.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var selectedTab: AppTab = .add {
        didSet { normalizeTab(previous: oldValue) }
    }
    @Published var advancedScreen: AdvancedScreen?
    /// Import to open once the advanced sheet has finished closing.
    private var importAfterAdvanced = false
    @Published var activeSession: SessionRequest?
    @Published var showImport = false
    @Published var importSubjectID: UUID?
    /// File handed to the app with "Open in Memora" / the share sheet, waiting to be imported.
    @Published var pendingImportURL: URL?
    /// Session to start once the import sheet has finished closing.
    var pendingSession: SessionRequest?

    func start(_ request: SessionRequest) {
        Haptics.tap()
        // A full-screen session can't be presented over an open sheet: close it first,
        // the session starts from the sheet's onDismiss.
        if advancedScreen != nil {
            pendingSession = request
            advancedScreen = nil
            return
        }
        activeSession = request
    }

    func openAdvanced(_ screen: AdvancedScreen) {
        advancedScreen = screen
    }

    /// Called from the advanced sheet's onDismiss.
    func advancedDidClose() {
        if importAfterAdvanced {
            importAfterAdvanced = false
            showImport = true
        } else {
            startPendingSession()
        }
    }

    /// Hidden tabs (old links, widgets, notifications) map onto the simple layout.
    private func normalizeTab(previous: AppTab) {
        switch selectedTab {
        case .home, .learn:
            selectedTab = .review
        case .coach:
            selectedTab = previous.isVisible ? previous : .add
            openAdvanced(.coach)
        case .analytics:
            selectedTab = previous.isVisible ? previous : .add
            openAdvanced(.analytics)
        default:
            if selectedTab != previous, advancedScreen != nil { advancedScreen = nil }
        }
    }

    /// Called from the import sheet's onDismiss, so the full-screen session is presented
    /// only after the sheet is fully gone (presenting during the dismissal is dropped by iOS).
    func startPendingSession() {
        guard let request = pendingSession else { return }
        pendingSession = nil
        start(request)
    }

    /// Called when a study session closes: opens a file that arrived in the meantime.
    func showPendingImport() {
        guard pendingImportURL != nil, !showImport else { return }
        importSubjectID = nil
        showImport = true
    }

    func openReview() {
        selectedTab = .review
        start(SessionRequest(mode: .smartReview))
    }

    func openImport(subjectID: UUID? = nil) {
        importSubjectID = subjectID
        if advancedScreen != nil {
            importAfterAdvanced = true
            advancedScreen = nil
            return
        }
        showImport = true
    }

    func handle(url: URL) {
        if url.isFileURL {
            pendingImportURL = url
            // An open import sheet picks the file up itself; a running study session is
            // not interrupted — the import opens when it closes (see showPendingImport).
            if showImport || activeSession != nil { return }
            importSubjectID = nil
            showImport = true
            return
        }
        guard url.scheme == "memora" else { return }
        switch url.host {
        case "review": openReview()
        case "learn": selectedTab = .learn
        case "import": selectedTab = .library; openImport()
        case "analytics": selectedTab = .analytics
        default: selectedTab = .add
        }
    }

    func handleNotificationAction(_ identifier: String) {
        openReview()
    }
}
