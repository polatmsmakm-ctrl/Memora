import SwiftUI
import UIKit

/// Invisible UIKit view placed behind a tour target. The guide asks it for its live
/// window frame, so the spotlight follows scrolling, rotation and size changes.
final class GuideProbeView: UIView {
    var anchorID: GuideAnchorID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let id = anchorID else { return }
        if window != nil {
            GuideCenter.shared.register(id, view: self)
        } else {
            GuideCenter.shared.unregister(id, view: self)
        }
    }
}

private struct GuideProbe: UIViewRepresentable {
    let id: GuideAnchorID

    func makeUIView(context: Context) -> GuideProbeView {
        let view = GuideProbeView(frame: .zero)
        view.anchorID = id
        return view
    }

    func updateUIView(_ uiView: GuideProbeView, context: Context) {
        if uiView.anchorID != id {
            uiView.anchorID = id
            if uiView.window != nil { GuideCenter.shared.register(id, view: uiView) }
        }
    }
}

/// Marks an element with a stable tour identifier.
private struct GuideAnchorModifier: ViewModifier {
    let id: GuideAnchorID

    func body(content: Content) -> some View {
        content.background(GuideProbe(id: id).allowsHitTesting(false).accessibilityHidden(true))
    }
}

/// Shows a one-time explanation bubble attached to this element the first time it appears.
private struct TipTaskKey: Equatable {
    let phase: GuideCenter.Phase
    let active: Bool
}

private struct FeatureTipModifier: ViewModifier {
    let tip: FeatureTip
    let arrowEdge: Edge
    /// False while the hosting screen is mounted but not visible (e.g. a background tab).
    let isActive: Bool
    @ObservedObject private var guide = GuideCenter.shared
    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $presented, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge) {
                FeatureTipBubble(tip: tip) { presented = false }
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(Color(red: 0.09, green: 0.095, blue: 0.13))
            }
            .task(id: TipTaskKey(phase: guide.phase, active: isActive)) {
                guard isActive else {
                    if presented { presented = false } else { guide.releaseTip(tip) }
                    return
                }
                guard !presented, !guide.isTipSeen(tip) else { return }
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }
                if guide.requestTip(tip) { presented = true }
            }
            .onChange(of: presented) { _, isPresented in
                if !isPresented { guide.dismissTip(tip) }
            }
            .onDisappear {
                if !presented { guide.releaseTip(tip) }
            }
    }
}

struct FeatureTipBubble: View {
    let tip: FeatureTip
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: tip.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.opacity(0.18), in: Circle())
                Text(tip.title).font(.headline).foregroundStyle(.white)
            }
            Text(tip.message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("guide.gotIt")) { onDismiss() }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(16)
        .frame(width: 290, alignment: .leading)
        .environment(\.layoutDirection, Localizer.language.layoutDirection)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Marks this element as a target of the guided tour.
    func guideAnchor(_ id: GuideAnchorID) -> some View {
        modifier(GuideAnchorModifier(id: id))
    }

    /// Attaches a one-time feature explanation to this element.
    func featureTip(_ tip: FeatureTip, arrowEdge: Edge = .top, isActive: Bool = true) -> some View {
        modifier(FeatureTipModifier(tip: tip, arrowEdge: arrowEdge, isActive: isActive))
    }
}
