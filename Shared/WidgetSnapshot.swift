import Foundation

/// Small summary written by the app into the shared App Group container and read by
/// the widget extension. Compiled into both targets.
struct WidgetSnapshot: Codable, Equatable {
    static let appGroupID = "group.com.rashid.memora"
    static let fileName = "widget-snapshot.json"

    /// Due dates of introduced items for the next few days (capped), so the widget can
    /// recompute "due now" at each timeline entry without the app running.
    var dueDates: [Date]
    var weakCount: Int
    var predictedRetention: Double?
    var reviewedToday: Int
    var secondsPerReview: Double
    var languageCode: String
    var updatedAt: Date

    static let empty = WidgetSnapshot(dueDates: [], weakCount: 0, predictedRetention: nil, reviewedToday: 0,
                                      secondsPerReview: 40, languageCode: "ar", updatedAt: Date())

    func dueCount(at date: Date) -> Int {
        dueDates.filter { $0 <= date }.count
    }

    func minutes(forCount count: Int) -> Int {
        guard count > 0 else { return 0 }
        return max(1, Int((Double(count) * secondsPerReview / 60).rounded(.up)))
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = containerURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Returns false when the App Group is not available (e.g. not enabled when signing).
    @discardableResult
    func save() -> Bool {
        guard let url = Self.containerURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(self) else { return false }
        return (try? data.write(to: url, options: [.atomic])) != nil
    }
}
