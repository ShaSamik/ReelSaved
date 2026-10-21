import SwiftUI

/// A slow-drifting mesh gradient that sits behind everything.
///
/// The motion is deliberately long-period — a full cycle takes the better part
/// of half a minute. Anything faster reads as a loading state rather than
/// atmosphere, and it has to stay calm underneath text.
struct AnimatedBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            Palette.base.ignoresSafeArea()

            MeshGradient(width: 3, height: 3, points: points, colors: Palette.mesh)
                .ignoresSafeArea()

            // A soft highlight near the top keeps the header from sitting on
            // flat colour and gives the whole thing a light source.
            RadialGradient(
                colors: [Palette.glow.opacity(0.16), .clear],
                center: .init(x: 0.5, y: drift ? 0.0 : 0.10),
                startRadius: 1,
                endRadius: 320
            )
            .ignoresSafeArea()
            .blendMode(.plusLighter)

            // Darkens the edges so the centre reads as lit and cards have
            // something to sit against at the top and bottom of the screen.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0.0),
                    .init(color: .clear, location: 0.28),
                    .init(color: .clear, location: 0.6),
                    .init(color: .black.opacity(0.65), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 26).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    /// Corners stay pinned so the gradient always fills the screen; only the
    /// edge midpoints and the centre wander.
    private var points: [SIMD2<Float>] {
        let d: Float = reduceMotion ? 0 : (drift ? 0.14 : -0.10)
        return [
            .init(0.0, 0.0), .init(0.5 + d * 0.35, 0.0), .init(1.0, 0.0),
            .init(0.0, 0.5 - d * 0.30), .init(0.5 + d, 0.5 + d * 0.45), .init(1.0, 0.5 + d * 0.30),
            .init(0.0, 1.0), .init(0.5 - d * 0.35, 1.0), .init(1.0, 1.0),
        ]
    }
}

enum Palette {
    static let base = Color(red: 0.035, green: 0.031, blue: 0.067)
    static let glow = Color(red: 0.49, green: 0.36, blue: 0.96)

    /// Nine stops for the 3×3 mesh. Kept dark and low-contrast so white text
    /// and glass cards stay readable wherever the gradient drifts.
    static let mesh: [Color] = [
        Color(red: 0.07, green: 0.06, blue: 0.14),
        Color(red: 0.17, green: 0.10, blue: 0.32),
        Color(red: 0.06, green: 0.07, blue: 0.18),

        Color(red: 0.23, green: 0.11, blue: 0.42),
        Color(red: 0.36, green: 0.16, blue: 0.62),
        Color(red: 0.10, green: 0.16, blue: 0.44),

        Color(red: 0.08, green: 0.06, blue: 0.17),
        Color(red: 0.28, green: 0.12, blue: 0.46),
        Color(red: 0.05, green: 0.09, blue: 0.24),
    ]

    static let accent = Color(red: 0.62, green: 0.45, blue: 1.0)
    static let accentSoft = Color(red: 0.42, green: 0.70, blue: 1.0)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentSoft],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
