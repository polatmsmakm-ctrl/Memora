import Foundation

/// Persistent onboarding state: whether the app tour was completed/skipped and which
/// one-time feature tips have been seen. Stored inside `AppDatabase` (and therefore in
/// backups) and mirrored in UserDefaults so a failed or quarantined database load can
/// never make the tour appear again.
struct GuidanceState: Codable, Equatable {
    var tourCompleted: Bool = false
    var tourSkipped: Bool = false
    var tourCompletedAt: Date? = nil
    var seenTips: [String] = []

    func hasSeenTip(_ id: String) -> Bool { seenTips.contains(id) }

    /// Union of two states: once completed or seen anywhere, it stays completed/seen.
    static func merged(_ a: GuidanceState, _ b: GuidanceState) -> GuidanceState {
        var result = a
        result.tourCompleted = a.tourCompleted || b.tourCompleted
        result.tourSkipped = a.tourSkipped || b.tourSkipped
        switch (a.tourCompletedAt, b.tourCompletedAt) {
        case let (x?, y?): result.tourCompletedAt = min(x, y)
        case let (x?, nil): result.tourCompletedAt = x
        case let (nil, y?): result.tourCompletedAt = y
        default: result.tourCompletedAt = nil
        }
        var tips = a.seenTips
        for tip in b.seenTips where !tips.contains(tip) { tips.append(tip) }
        result.seenTips = tips
        return result
    }
}

extension GuidanceState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GuidanceState()
        self = d
        tourCompleted = c.decode(.tourCompleted, default: d.tourCompleted)
        tourSkipped = c.decode(.tourSkipped, default: d.tourSkipped)
        tourCompletedAt = c.decode(.tourCompletedAt, default: d.tourCompletedAt)
        seenTips = c.decode(.seenTips, default: d.seenTips)
    }
}

/// Secondary copy of the onboarding state in UserDefaults.
struct GuidanceMirror {
    static let standard = GuidanceMirror(defaults: .standard)
    static let tourKey = "memora.guidance.tourCompleted"
    static let tipsKey = "memora.guidance.seenTips"

    let defaults: UserDefaults

    var tourCompleted: Bool { defaults.bool(forKey: Self.tourKey) }
    var seenTips: [String] { defaults.stringArray(forKey: Self.tipsKey) ?? [] }

    /// Combines the database state with the mirror (never loses a completion).
    func reconcile(_ state: GuidanceState) -> GuidanceState {
        var mirrorState = GuidanceState()
        mirrorState.tourCompleted = tourCompleted
        mirrorState.seenTips = seenTips
        return GuidanceState.merged(state, mirrorState)
    }

    func save(_ state: GuidanceState) {
        defaults.set(state.tourCompleted, forKey: Self.tourKey)
        defaults.set(state.seenTips, forKey: Self.tipsKey)
    }
}
