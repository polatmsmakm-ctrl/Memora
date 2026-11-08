import SwiftUI
import UIKit

/// Coordinates the first-time tour and the one-time feature tips.
///
/// - The tour starts automatically only when the persisted state says it was never
///   completed or skipped (database and UserDefaults mirror both checked).
/// - Element frames are reported by `.guideAnchor(_:)` in global coordinates, so the
///   spotlight follows the real control on every screen size and orientation.
/// - Only one tip is presented at a time and never while the tour is running.
@MainActor
final class GuideCenter: ObservableObject {
    static let shared = GuideCenter()

    enum Phase: Equatable {
        case idle
        case welcome
        case step(Int)
        case finished
    }

    @Published private(set) var phase: Phase = .idle
    /// Element the current step wants scrolled into view (observed by scrollable screens).
    @Published private(set) var scrollRequest: GuideAnchorID?
    @Published private(set) var activeTip: FeatureTip?

    private weak var store: MemoraStore?
    private weak var router: AppRouter?

    let steps = GuideTour.steps

    var isTourVisible: Bool { phase != .idle }

    var currentIndex: Int? {
        if case .step(let index) = phase { return index }
        return nil
    }

    var currentStep: TourStep? {
        guard let index = currentIndex, steps.indices.contains(index) else { return nil }
        return steps[index]
    }

    var hasCompletedTour: Bool {
        (store?.guidance.tourCompleted ?? false) || GuidanceMirror.standard.tourCompleted
    }

    func attach(store: MemoraStore, router: AppRouter) {
        self.store = store
        self.router = router
    }

    // MARK: Tour

    /// Called on launch. Shows the welcome screen only for users who never finished or skipped it.
    func startIfNeeded() {
        guard store != nil, !hasCompletedTour, phase == .idle else { return }
        guard router?.activeSession == nil, router?.showImport != true else { return }
        activeTip = nil
        withAnimation(.easeInOut(duration: 0.3)) { phase = .welcome }
    }

    /// Manual replay from Settings. Learning data and preferences are untouched.
    func replay() {
        activeTip = nil
        router?.activeSession = nil
        router?.showImport = false
        router?.selectedTab = .home
        withAnimation(.easeInOut(duration: 0.3)) { phase = .welcome }
    }

    func beginSteps() {
        go(to: 0)
    }

    func next() {
        guard let index = currentIndex else { return }
        if index + 1 < steps.count {
            go(to: index + 1)
        } else {
            Haptics.success()
            withAnimation(.easeInOut(duration: 0.3)) { phase = .finished }
        }
    }

    func back() {
        guard let index = currentIndex, index > 0 else { return }
        go(to: index - 1)
    }

    func skip() {
        complete(skipped: true)
    }

    func finish() {
        complete(skipped: false)
    }

    private func complete(skipped: Bool) {
        store?.markTourFinished(skipped: skipped)
        scrollRequest = nil
        router?.selectedTab = .home
        withAnimation(.easeInOut(duration: 0.3)) { phase = .idle }
    }

    private func go(to index: Int) {
        guard steps.indices.contains(index) else { return }
        let step = steps[index]
        Haptics.selection()
        router?.selectedTab = step.tab
        scrollRequest = step.anchor
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { phase = .step(index) }
    }

    // MARK: Anchors

    private final class WeakProbe {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }

    private var probes: [GuideAnchorID: WeakProbe] = [:]

    func register(_ id: GuideAnchorID, view: UIView) {
        probes[id] = WeakProbe(view)
    }

    func unregister(_ id: GuideAnchorID, view: UIView) {
        if probes[id]?.view === view { probes[id] = nil }
    }

    /// Live frame of an element in its window's coordinates (UIKit coordinates are never
    /// mirrored for right-to-left layouts, so Arabic and English behave identically).
    func liveFrame(for id: GuideAnchorID) -> CGRect? {
        guard let view = probes[id]?.view, let window = view.window else { return nil }
        let frame = view.convert(view.bounds, to: window)
        guard frame.width > 0, frame.height > 0, frame.minX.isFinite, frame.minY.isFinite else { return nil }
        return frame
    }

    // MARK: Feature tips

    func isTipSeen(_ tip: FeatureTip) -> Bool {
        (store?.guidance.hasSeenTip(tip.rawValue) ?? false) || GuidanceMirror.standard.seenTips.contains(tip.rawValue)
    }

    /// Grants the presentation slot to a tip if it was never seen, the tour is finished
    /// and no other tip is showing.
    func requestTip(_ tip: FeatureTip) -> Bool {
        guard store != nil, hasCompletedTour, phase == .idle, !isTipSeen(tip) else { return false }
        if let active = activeTip { return active == tip }
        activeTip = tip
        return true
    }

    /// Marks a tip as seen (it never appears again automatically) and frees the slot.
    func dismissTip(_ tip: FeatureTip) {
        store?.markTipSeen(tip.rawValue)
        if activeTip == tip { activeTip = nil }
    }

    /// Frees the slot without marking the tip as seen (view disappeared before it showed).
    func releaseTip(_ tip: FeatureTip) {
        if activeTip == tip { activeTip = nil }
    }

    func resetTips() {
        store?.resetFeatureTips()
        activeTip = nil
    }
}
