import SwiftUI

/// Help section: replay the tour, read every tour explanation and feature tip at any
/// time, and optionally let the one-time tips appear again. Never touches learning data.
struct HelpCenterView: View {
    @EnvironmentObject private var store: MemoraStore
    @ObservedObject private var guide = GuideCenter.shared
    @State private var tipsReset = false

    var body: some View {
        List {
            Section {
                Button {
                    guide.replay()
                } label: {
                    Label(L("help.replay"), systemImage: "play.circle")
                }
                Text(L("help.replay.note")).font(.caption).foregroundStyle(.secondary)
                if let date = store.guidance.tourCompletedAt {
                    Text(LF("help.tourDoneOn", Formatters.date(date))).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(L("help.tour"))
            }
            .listRowBackground(Theme.surface)

            Section(L("help.screens")) {
                ForEach(guide.steps) { step in
                    DisclosureGroup {
                        Text(step.message).font(.callout).foregroundStyle(.secondary).padding(.vertical, 4)
                    } label: {
                        Label(step.title, systemImage: step.systemImage)
                    }
                }
            }
            .listRowBackground(Theme.surface)

            Section {
                ForEach(FeatureTip.allCases) { tip in
                    DisclosureGroup {
                        Text(tip.message).font(.callout).foregroundStyle(.secondary).padding(.vertical, 4)
                    } label: {
                        HStack {
                            Label(tip.title, systemImage: tip.systemImage)
                            Spacer()
                            if guide.isTipSeen(tip) {
                                Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
                                    .accessibilityLabel(L("help.seen"))
                            }
                        }
                    }
                }
                Button {
                    guide.resetTips()
                    tipsReset = true
                    Haptics.success()
                } label: {
                    Label(L("help.resetTips"), systemImage: "arrow.counterclockwise")
                }
                if tipsReset {
                    Text(L("help.resetTips.done")).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(L("help.tips"))
            } footer: {
                Text(L("help.tips.footer"))
            }
            .listRowBackground(Theme.surface)
        }
        .memoraScreen()
        .navigationTitle(L("settings.help"))
    }
}
