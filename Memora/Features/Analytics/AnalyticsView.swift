import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject private var store: MemoraStore
    @EnvironmentObject private var router: AppRouter
    @State private var snapshot = AnalyticsSnapshot()
    @State private var computedAt: Date?
    @State private var isStale = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    disclaimer
                    if store.db.reviewLogs.isEmpty && store.db.items.isEmpty {
                        EmptyStateView(systemImage: "chart.xyaxis.line", title: L("analytics.empty.title"), message: L("analytics.empty.message"))
                    } else {
                        overview
                        upcomingChart
                        trendChart
                        statesChart
                        calibrationSection
                        masteryChart
                        transferSection
                        subjectsSection
                        consistencySection
                        errorsSection
                        pretestSection
                    }
                    NavigationLink { ExperimentsView() } label: {
                        GlassCard {
                            HStack(spacing: 12) {
                                Image(systemName: "flask").font(.title2).foregroundStyle(Theme.violet)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("experiments.title")).font(.headline)
                                    Text(L("experiments.subtitle")).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(Theme.padding)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .memoraScreen()
            .navigationTitle(L("tab.analytics"))
            .onAppear { if isVisible { recompute() } }
            // On iPhone every tab stays alive; recomputing the whole dashboard after each
            // answer while it is hidden slowed study sessions down. Recompute when shown.
            .onChange(of: store.db.lastModified) { _, _ in
                if isVisible { recompute() } else { isStale = true }
            }
            .onChange(of: router.selectedTab) { _, tab in
                if tab == .analytics && isStale { recompute() }
            }
            .refreshable { recompute() }
        }
    }

    private var isVisible: Bool { router.selectedTab == .analytics }

    private func recompute() {
        snapshot = AnalyticsEngine.compute(db: store.db, scheduler: store.scheduler, now: Date())
        computedAt = Date()
        isStale = false
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(L("analytics.disclaimer")).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overview: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            StatTile(title: L("analytics.learned"), value: "\(snapshot.learnedItems)/\(snapshot.totalItems)", systemImage: "square.stack.3d.up")
            StatTile(title: L("analytics.success"), value: "\(snapshot.successfulRetrievals)", systemImage: "checkmark.circle", tint: Theme.success)
            StatTile(title: L("analytics.failed"), value: "\(snapshot.failedRetrievals)", systemImage: "xmark.circle", tint: Theme.danger,
                     footnote: LF("analytics.partialCount", snapshot.partialRetrievals))
            StatTile(title: L("analytics.measured30"), value: Formatters.percent(snapshot.measuredRecall30), systemImage: "ruler",
                     tint: Theme.success, footnote: L("analytics.measuredNote"))
            StatTile(title: L("analytics.predicted"), value: Formatters.percent(snapshot.predictedRetentionNow), systemImage: "function",
                     tint: Theme.violet, footnote: L("analytics.predictedNote"))
            StatTile(title: L("analytics.overdue"), value: "\(snapshot.overdue)", systemImage: "clock.badge.exclamationmark", tint: Theme.warning,
                     footnote: LF("analytics.dueToday", snapshot.dueToday))
            StatTile(title: L("analytics.delayed"), value: Formatters.percent(snapshot.delayedRecall.rate), systemImage: "hourglass",
                     footnote: LF("analytics.delayedN", snapshot.delayedRecall.attempts))
            StatTile(title: L("analytics.time"), value: LF("unit.minutesShort", Int(snapshot.minutes7.rounded())), systemImage: "timer",
                     footnote: LF("analytics.timeTotal", Int(snapshot.minutesTotal.rounded())))
        }
    }

    private var upcomingChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: L("analytics.upcoming"), subtitle: L("analytics.upcoming.subtitle"), systemImage: "calendar")
                Chart(snapshot.upcoming) { day in
                    BarMark(x: .value(L("analytics.day"), day.day, unit: .day), y: .value(L("analytics.reviews"), day.count))
                        .foregroundStyle(Theme.accent.gradient)
                        .cornerRadius(4)
                }
                .frame(height: 160)
            }
        }
    }

    @ViewBuilder
    private var trendChart: some View {
        if !snapshot.trend.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: L("analytics.trend"), subtitle: L("analytics.trend.subtitle"), systemImage: "chart.line.uptrend.xyaxis")
                    Chart {
                        ForEach(snapshot.trend) { point in
                            LineMark(x: .value(L("analytics.week"), point.weekStart, unit: .weekOfYear),
                                     y: .value(L("analytics.rate"), point.measuredRecall),
                                     series: .value("series", L("analytics.measured")))
                                .foregroundStyle(Theme.success)
                                .symbol(.circle)
                            LineMark(x: .value(L("analytics.week"), point.weekStart, unit: .weekOfYear),
                                     y: .value(L("analytics.rate"), point.predictedRecall),
                                     series: .value("series", L("analytics.predictedShort")))
                                .foregroundStyle(Theme.violet)
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        }
                    }
                    .chartYScale(domain: 0...1)
                    .chartYAxis {
                        AxisMarks(values: [0.0, 0.25, 0.5, 0.75, 1.0]) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) { Text(Formatters.percent(v)) }
                            }
                        }
                    }
                    .frame(height: 180)
                    HStack(spacing: 14) {
                        legendDot(Theme.success, L("analytics.measured"))
                        legendDot(Theme.violet, L("analytics.predictedShort"))
                    }
                }
            }
        }
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var statesChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: L("analytics.states"), systemImage: "square.stack.3d.up")
                Chart(MemoryState.allCases) { state in
                    BarMark(x: .value(L("analytics.count"), snapshot.stateCounts[state] ?? 0), y: .value(L("analytics.state"), state.title))
                        .foregroundStyle(Theme.color(for: state))
                        .cornerRadius(4)
                }
                .frame(height: 220)
            }
        }
    }

    private var calibrationSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: L("analytics.calibration"), subtitle: L("analytics.calibration.subtitle"), systemImage: "gauge.with.dots.needle.50percent")
                if snapshot.calibration.isEmpty {
                    Text(L("analytics.notEnough")).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Chart {
                        ForEach(snapshot.calibration) { bin in
                            BarMark(x: .value(L("analytics.confidence"), bin.level.title), y: .value(L("analytics.accuracy"), bin.observed))
                                .foregroundStyle(Theme.accent)
                                .annotation(position: .top) { Text("n=\(bin.count)").font(.caption2).foregroundStyle(.secondary) }
                            PointMark(x: .value(L("analytics.confidence"), bin.level.title),
                                      y: .value(L("analytics.expected"), bin.expected))
                                .foregroundStyle(Theme.warning)
                                .symbol(.diamond)
                                .symbolSize(90)
                        }
                    }
                    .chartYScale(domain: 0...1)
                    .frame(height: 180)
                    Text(L("analytics.calibration.legend")).font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    Text(CalibrationAnalyzer.label(for: snapshot.calibrationBias).title).font(.callout.weight(.semibold))
                    Spacer()
                    if let brier = snapshot.brierScore {
                        Text("Brier \(Formatters.number(brier, digits: 2))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var masteryChart: some View {
        if snapshot.mastery.contains(where: { $0.cumulative > 0 }) {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: L("analytics.mastery"), subtitle: L("analytics.mastery.subtitle"), systemImage: "checkmark.seal")
                    Chart(snapshot.mastery) { point in
                        AreaMark(x: .value(L("analytics.week"), point.weekStart, unit: .weekOfYear), y: .value(L("analytics.count"), point.cumulative))
                            .foregroundStyle(Theme.success.opacity(0.3).gradient)
                        LineMark(x: .value(L("analytics.week"), point.weekStart, unit: .weekOfYear), y: .value(L("analytics.count"), point.cumulative))
                            .foregroundStyle(Theme.success)
                    }
                    .frame(height: 160)
                }
            }
        }
    }

    private var transferSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: L("analytics.transfer"), subtitle: L("analytics.transfer.subtitle"), systemImage: "arrow.triangle.branch")
                ForEach(snapshot.buckets, id: \.0) { bucket, tally in
                    HStack {
                        Text(bucket.title).font(.callout).frame(width: 110, alignment: .leading)
                        ProgressBar(value: tally.rate ?? 0, tint: Theme.accent)
                        Text(tally.attempts == 0 ? "—" : Formatters.percent(tally.rate)).font(.caption.monospacedDigit()).frame(width: 44, alignment: .trailing)
                        Text("n=\(tally.attempts)").font(.caption2).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var subjectsSection: some View {
        let ranked = snapshot.subjects.filter { $0.attempts >= 3 }.sorted { ($0.measuredRecall ?? 0) > ($1.measuredRecall ?? 0) }
        if !ranked.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: L("analytics.subjects"), subtitle: L("analytics.subjects.subtitle"), systemImage: "books.vertical")
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, stat in
                        HStack {
                            if index == 0 && ranked.count > 1 { Image(systemName: "arrow.up.circle.fill").foregroundStyle(Theme.success) }
                            if index == ranked.count - 1 && ranked.count > 1 { Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.danger) }
                            Text(stat.name).font(.callout).lineLimit(1)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(LF("analytics.measuredValue", Formatters.percent(stat.measuredRecall))).font(.caption.monospacedDigit())
                                Text(LF("analytics.predictedValue", Formatters.percent(stat.predictedRetention))).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var consistencySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: L("analytics.consistency"), subtitle: LF("analytics.consistency.subtitle", snapshot.activeDays30), systemImage: "calendar.badge.checkmark")
                let maxReviews = max(1, snapshot.activity.map(\.reviews).max() ?? 1)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
                    ForEach(snapshot.activity) { day in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(day.reviews == 0 ? Theme.stroke : Theme.accent.opacity(0.25 + 0.75 * Double(day.reviews) / Double(maxReviews)))
                            .frame(height: 18)
                            .accessibilityLabel(Formatters.date(day.day) + ": \(day.reviews)")
                    }
                }
                Text(L("analytics.consistency.note")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var errorsSection: some View {
        if !snapshot.errorBreakdown.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: L("analytics.errors"), systemImage: "exclamationmark.triangle")
                    ForEach(snapshot.errorBreakdown, id: \.0) { category, count in
                        HStack {
                            Label(category.title, systemImage: category.systemImage).font(.callout)
                            Spacer()
                            Text("\(count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pretestSection: some View {
        if snapshot.pretestCount > 0 {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: L("analytics.pretest"), subtitle: LF("analytics.pretest.subtitle", snapshot.pretestCount), systemImage: "questionmark.circle")
                    HStack {
                        StatTile(title: L("analytics.pretest.before"), value: Formatters.percent(snapshot.pretestBefore), systemImage: "arrow.down.to.line")
                        StatTile(title: L("analytics.pretest.after"), value: Formatters.percent(snapshot.pretestAfter), systemImage: "arrow.up.to.line", tint: Theme.success)
                    }
                }
            }
        }
    }
}
