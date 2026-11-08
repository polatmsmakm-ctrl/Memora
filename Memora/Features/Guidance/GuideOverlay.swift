import SwiftUI

/// Full-screen tour layer: dims the interface, cuts a spotlight around the real element
/// of the current step and places a tooltip bubble with an arrow pointing at it.
/// Geometry is computed left-to-right in window coordinates; bubble text follows the
/// app language (RTL for Arabic).
struct GuideOverlay: View {
    @ObservedObject private var guide = GuideCenter.shared
    @EnvironmentObject private var store: MemoraStore
    @State private var bubbleSize = CGSize(width: 320, height: 190)

    private let dim = Color.black.opacity(0.68)

    var body: some View {
        if guide.isTourVisible {
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                ZStack {
                    switch guide.phase {
                    case .welcome:
                        dim.contentShape(Rectangle()).onTapGesture {}
                        TourCard(kind: .welcome, guide: guide)
                            .frame(maxWidth: min(420, proxy.size.width - 32))
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    case .finished:
                        dim.contentShape(Rectangle()).onTapGesture {}
                        TourCard(kind: .finished, guide: guide)
                            .frame(maxWidth: min(420, proxy.size.width - 32))
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    case .step(let index):
                        // Re-measures the target a few times per second so the spotlight
                        // follows scrolling, rotation and keyboard/layout changes.
                        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                            stepLayer(index: index, canvas: proxy.size, origin: origin)
                        }
                    case .idle:
                        EmptyView()
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()
            .environment(\.layoutDirection, .leftToRight)
            .transition(.opacity)
            .accessibilityAddTraits(.isModal)
        }
    }

    // MARK: Step layer

    @ViewBuilder
    private func stepLayer(index: Int, canvas: CGSize, origin: CGPoint) -> some View {
        let step = guide.steps[index]
        let hole = spotlightRect(for: step, canvas: canvas, origin: origin)
        let radius = hole.map { min(18, $0.height / 2) } ?? 0
        let placement = bubblePlacement(hole: hole, canvas: canvas)

        SpotlightShape(hole: hole ?? .zero, cornerRadius: radius)
            .fill(dim, style: FillStyle(eoFill: true))
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: hole)
            .contentShape(Rectangle())
            .onTapGesture {}
            .accessibilityHidden(true)

        if let hole {
            PulseRing(rect: hole, cornerRadius: radius)
                .id(index)
                .accessibilityHidden(true)
        }

        TourBubble(step: step, index: index, total: guide.steps.count,
                   arrowX: placement.arrowX, arrowOnTop: placement.arrowOnTop, guide: guide)
            .frame(width: placement.width)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: BubbleSizeKey.self, value: geo.size)
                }
            )
            .onPreferenceChange(BubbleSizeKey.self) { size in
                if abs(size.height - bubbleSize.height) > 0.5 || abs(size.width - bubbleSize.width) > 0.5 {
                    bubbleSize = size
                }
            }
            .position(placement.center)
            .id("bubble-\(index)")
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: placement.center)
    }

    /// Frame of the element in overlay coordinates, padded; nil when it is not on screen.
    private func spotlightRect(for step: TourStep, canvas: CGSize, origin: CGPoint) -> CGRect? {
        guard let global = guide.liveFrame(for: step.anchor) else { return nil }
        let local = global.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -8, dy: -6)
        let screen = CGRect(origin: .zero, size: canvas)
        guard screen.intersects(local), local.width < canvas.width * 1.2, local.height < canvas.height * 0.85 else { return nil }
        return local.intersection(screen.insetBy(dx: 2, dy: 2))
    }

    private struct Placement {
        var center: CGPoint
        var width: CGFloat
        var arrowX: CGFloat?
        var arrowOnTop: Bool
    }

    private func bubblePlacement(hole: CGRect?, canvas: CGSize) -> Placement {
        let width = min(360, canvas.width - 32)
        let height = bubbleSize.height
        let topLimit: CGFloat = 54
        let bottomLimit: CGFloat = canvas.height - 34
        guard let hole else {
            return Placement(center: CGPoint(x: canvas.width / 2, y: canvas.height / 2), width: width, arrowX: nil, arrowOnTop: true)
        }
        let gap: CGFloat = 16
        let spaceBelow = bottomLimit - hole.maxY - gap
        let spaceAbove = hole.minY - gap - topLimit
        let below = spaceBelow >= height || spaceBelow >= spaceAbove
        var centerY: CGFloat
        if below {
            centerY = hole.maxY + gap + height / 2
            centerY = min(centerY, bottomLimit - height / 2)
        } else {
            centerY = hole.minY - gap - height / 2
            centerY = max(centerY, topLimit + height / 2)
        }
        let half = width / 2
        let centerX = min(max(hole.midX, 16 + half), canvas.width - 16 - half)
        let arrowX = min(max(hole.midX - (centerX - half), 26), width - 26)
        return Placement(center: CGPoint(x: centerX, y: centerY), width: width, arrowX: arrowX, arrowOnTop: below)
    }
}

private struct BubbleSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Dimmed rectangle with an animated rounded cut-out.
struct SpotlightShape: Shape {
    var hole: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(hole.origin.x, hole.origin.y), AnimatablePair(hole.size.width, hole.size.height))
        }
        set {
            hole = CGRect(x: newValue.first.first, y: newValue.first.second,
                          width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if hole.width > 1 && hole.height > 1 {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
        }
        return path
    }
}

private struct PulseRing: View {
    let rect: CGRect
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Theme.accent, lineWidth: 2)
            RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                .stroke(Theme.accent.opacity(0.6), lineWidth: 2)
                .padding(-5)
                .scaleEffect(pulse ? 1.05 : 1)
                .opacity(pulse ? 0 : 0.8)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

private struct ArrowShape: Shape {
    var pointsUp: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsUp {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

private let bubbleFill = Color(red: 0.085, green: 0.09, blue: 0.125)

/// Tooltip bubble for one tour step, with arrow, progress and controls.
private struct TourBubble: View {
    let step: TourStep
    let index: Int
    let total: Int
    let arrowX: CGFloat?
    let arrowOnTop: Bool
    @ObservedObject var guide: GuideCenter

    var body: some View {
        VStack(spacing: 0) {
            if arrowOnTop, let arrowX { arrow(x: arrowX, up: true) }
            content
                .padding(16)
                .background(bubbleFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.accent.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            if !arrowOnTop, let arrowX { arrow(x: arrowX, up: false) }
        }
    }

    private func arrow(x: CGFloat, up: Bool) -> some View {
        GeometryReader { geo in
            ArrowShape(pointsUp: up)
                .fill(bubbleFill)
                .frame(width: 20, height: 10)
                .position(x: min(max(x, 10), geo.size.width - 10), y: 5)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: step.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title).font(.headline).foregroundStyle(.white)
                    Text(LF("guide.stepOf", index + 1, total))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            Text(step.message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            ProgressDots(current: index, total: total)
            HStack(spacing: 10) {
                Button(L("guide.skip")) { guide.skip() }
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if index > 0 {
                    Button { guide.back() } label: {
                        Image(systemName: "chevron.backward")
                            .font(.callout.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel(L("guide.back"))
                }
                Button(index + 1 == total ? L("guide.finish") : L("guide.next")) { guide.next() }
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .environment(\.layoutDirection, Localizer.language.layoutDirection)
        .accessibilityElement(children: .contain)
    }
}

private struct ProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Theme.accent : Color.white.opacity(i < current ? 0.45 : 0.18))
                    .frame(width: i == current ? 18 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: current)
        .accessibilityHidden(true)
    }
}

/// Welcome and completion cards.
private struct TourCard: View {
    enum Kind { case welcome, finished }
    let kind: Kind
    @ObservedObject var guide: GuideCenter

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: kind == .welcome ? "brain.head.profile" : "checkmark.seal.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(kind == .welcome ? Theme.accent : Theme.success)
                .frame(width: 76, height: 76)
                .background((kind == .welcome ? Theme.accent : Theme.success).opacity(0.16), in: Circle())
            Text(kind == .welcome ? L("guide.welcome.title") : L("guide.finished.title"))
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(kind == .welcome ? LF("guide.welcome.body", guide.steps.count) : L("guide.finished.body"))
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if kind == .welcome {
                Button(L("guide.start")) { guide.beginSteps() }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                Button(L("guide.skipTutorial")) { guide.skip() }
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
                    .buttonStyle(.plain)
            } else {
                Button(L("guide.done")) { guide.finish() }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            }
        }
        .padding(24)
        .background(bubbleFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.accent.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .environment(\.layoutDirection, Localizer.language.layoutDirection)
        .accessibilityElement(children: .contain)
    }
}
