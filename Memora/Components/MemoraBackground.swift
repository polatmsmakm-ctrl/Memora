import SwiftUI

/// Code-drawn backdrop: near-black surface with two slow, faint accent glows.
/// Replaceable by photo backgrounds (add an image set named "Background" to the asset
/// catalog and it is used automatically under a dark overlay).
struct MemoraBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            Theme.background
            if let image = UIImage(named: "Background") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay(Color.black.opacity(scheme == .dark ? 0.62 : 0.25))
            }
            Circle()
                .fill(Theme.accent.opacity(scheme == .dark ? 0.16 : 0.08))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: animate ? 120 : -90, y: animate ? -280 : -200)
            Circle()
                .fill(Theme.violet.opacity(scheme == .dark ? 0.10 : 0.05))
                .frame(width: 360, height: 360)
                .blur(radius: 120)
                .offset(x: animate ? -130 : 110, y: animate ? 320 : 240)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) { animate = true }
        }
    }
}

extension View {
    /// Standard screen chrome: background behind lists/forms/scroll views.
    func memoraScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { MemoraBackground() }
    }
}
