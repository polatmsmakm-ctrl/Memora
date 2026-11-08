import WidgetKit
import SwiftUI

struct MemoraEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var dueNow: Int { snapshot.dueCount(at: date) }
}

struct MemoraProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemoraEntry {
        MemoraEntry(date: Date(), snapshot: WidgetSnapshot(dueDates: Array(repeating: Date(), count: 8), weakCount: 2,
                                                           predictedRetention: 0.9, reviewedToday: 12, secondsPerReview: 40,
                                                           languageCode: "ar", updatedAt: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (MemoraEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : MemoraEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .empty))
    }

    /// Hourly entries for the next 12 hours; due counts are recomputed from stored due dates.
    func getTimeline(in context: Context, completion: @escaping (Timeline<MemoraEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? .empty
        let now = Date()
        var entries: [MemoraEntry] = [MemoraEntry(date: now, snapshot: snapshot)]
        let upcoming = snapshot.dueDates.filter { $0 > now && $0 < now.addingTimeInterval(12 * 3600) }
        var marks = Set<Date>()
        for hour in 1...12 { marks.insert(now.addingTimeInterval(Double(hour) * 3600)) }
        for date in upcoming.prefix(20) { marks.insert(date.addingTimeInterval(1)) }
        for date in marks.sorted() { entries.append(MemoraEntry(date: date, snapshot: snapshot)) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(12 * 3600))))
    }
}

private enum WidgetText {
    static func t(_ key: String, _ lang: String) -> String {
        let ar: [String: String] = [
            "due": "للمراجعة الآن",
            "minutes": "≈ %d د",
            "weak": "ضعيفة",
            "retention": "احتفاظ متوقع",
            "today": "اليوم",
            "allDone": "لا شيء مستحق",
            "title": "ميمورا"
        ]
        let en: [String: String] = [
            "due": "due now",
            "minutes": "≈ %d min",
            "weak": "weak",
            "retention": "predicted retention",
            "today": "today",
            "allDone": "Nothing due",
            "title": "Memora"
        ]
        return (lang == "ar" ? ar[key] : en[key]) ?? key
    }
}

private let accent = Color(red: 0.49, green: 0.55, blue: 1.0)

struct MemoraWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MemoraEntry

    private var lang: String { entry.snapshot.languageCode }
    private var direction: LayoutDirection { lang == "ar" ? .rightToLeft : .leftToRight }

    var body: some View {
        content
            .environment(\.layoutDirection, direction)
            .widgetURL(URL(string: "memora://review"))
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red: 0.05, green: 0.055, blue: 0.075), Color(red: 0.03, green: 0.033, blue: 0.045)],
                               startPoint: .top, endPoint: .bottom)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(min(entry.dueNow, 50)), in: 0...50) {
                Image(systemName: "brain.head.profile")
            } currentValueLabel: {
                Text("\(entry.dueNow)").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(WidgetText.t("title", lang)).font(.headline)
                Text("\(entry.dueNow) " + WidgetText.t("due", lang)).monospacedDigit()
                if entry.dueNow > 0 {
                    Text(String(format: WidgetText.t("minutes", lang), entry.snapshot.minutes(forCount: entry.dueNow))).font(.caption)
                }
            }
        case .accessoryInline:
            Text("Memora · \(entry.dueNow) " + WidgetText.t("due", lang))
        case .systemMedium:
            HStack(spacing: 16) {
                dueBlock
                Divider().overlay(Color.white.opacity(0.15))
                VStack(alignment: .leading, spacing: 8) {
                    stat("exclamationmark.triangle", "\(entry.snapshot.weakCount)", WidgetText.t("weak", lang))
                    stat("function", entry.snapshot.predictedRetention.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", WidgetText.t("retention", lang))
                    stat("checkmark.circle", "\(entry.snapshot.reviewedToday)", WidgetText.t("today", lang))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
        default:
            dueBlock.foregroundStyle(.white)
        }
    }

    private var dueBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "brain.head.profile").foregroundStyle(accent)
            Spacer(minLength: 0)
            Text("\(entry.dueNow)")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
            Text(entry.dueNow == 0 ? WidgetText.t("allDone", lang) : WidgetText.t("due", lang))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            if entry.dueNow > 0 {
                Text(String(format: WidgetText.t("minutes", lang), entry.snapshot.minutes(forCount: entry.dueNow)))
                    .font(.caption2)
                    .foregroundStyle(accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(accent).frame(width: 16)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
    }
}

struct MemoraWidget: Widget {
    let kind = "MemoraWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemoraProvider()) { entry in
            MemoraWidgetView(entry: entry)
        }
        .configurationDisplayName("Memora")
        .description("Reviews approaching their predicted forgetting point.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct MemoraWidgetBundle: WidgetBundle {
    var body: some Widget {
        MemoraWidget()
    }
}
