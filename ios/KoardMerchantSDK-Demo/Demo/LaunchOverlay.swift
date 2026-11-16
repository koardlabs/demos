import SwiftUI

/// Bridging splash screen that takes over from `LaunchScreen.storyboard`
/// the moment SwiftUI starts rendering, and stays up just long enough
/// for the heavy first-frame work (Metal shader compilation for the
/// numeric-text transition, asset cache warm-up, view tree compilation)
/// to complete *behind it*.
///
/// Visually identical to the storyboard (white background + centered
/// Koard logo) so the handoff is seamless. After `holdFor` elapses,
/// fades out to reveal the real UI underneath.
struct LaunchOverlay: View {
    /// How long to keep the overlay visible before fading. 800 ms is
    /// long enough for shader compilation + initial Observable setup +
    /// SwiftUI layout pass on a fresh install. Shorter feels snappier
    /// but risks the cold-start lag bleeding through.
    var holdFor: Duration = .milliseconds(800)
    /// How long the fade-out lasts. Snappy enough not to feel slow,
    /// long enough to look intentional.
    var fadeDuration: Double = 0.35
    let onDismiss: () -> Void

    @State private var isHiding = false

    /// The koardLogo PDF asset, force-loaded via UIImage so we can
    /// branch on whether it's actually available. If the asset fails to
    /// load (transient launch-time issue, missing from a stripped
    /// build, etc.) we fall back to the brand wordmark in text — the
    /// splash never goes blank.
    private static let logoImage: UIImage? = UIImage(named: "koardLogo")

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 18) {
                // Logo: explicitly sized to ~280pt wide and 60pt tall.
                // The old maxWidth:240 + 40pt-tall PDF rendered at
                // 240x40 — easily lost on a full-screen white field.
                // Sizing it 7x bigger by area + explicit height means
                // it's actually visible, and `aspectRatio(.fit)` keeps
                // the proportions correct.
                if let logoImage = Self.logoImage {
                    Image(uiImage: logoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 280, maxHeight: 60)
                }

                // Brand wordmark as a guaranteed-visible fallback +
                // reinforcement under the logo. Even if the PDF asset
                // can't be loaded for any reason, the user sees
                // "Koard" prominently in the brand green.
                Text("Koard")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.koardGreen)
                    .tracking(0.5)

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.koardGreen)
                    .scaleEffect(1.1)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 40)
        }
        .opacity(isHiding ? 0 : 1)
        .task {
            try? await Task.sleep(for: holdFor)
            withAnimation(.easeOut(duration: fadeDuration)) {
                isHiding = true
            }
            try? await Task.sleep(for: .milliseconds(Int(fadeDuration * 1000)))
            onDismiss()
        }
    }
}

/// Invisible, off-screen view whose sole job is to trigger
/// `.contentTransition(.numericText())` a handful of times the moment
/// SwiftUI starts rendering. The transition has Metal shaders that
/// compile lazily on first use — the first time *anywhere* in the app
/// that a numericText transition fires, the user pays a ~100–250 ms hit
/// because the GPU pipeline has to compile.
///
/// Cycling a hidden counter here during the launch overlay means by the
/// time the user reaches the pin pad, the shader is already compiled,
/// the keystroke→amount animation runs at the full frame rate.
struct NumericTextShaderWarmup: View {
    @State private var counter = 0

    var body: some View {
        Text("\(counter)")
            .contentTransition(.numericText())
            .animation(.linear(duration: 0.01), value: counter)
            // Match the real pin-pad usage so the shader variant we
            // compile is the same one the user will actually hit.
            .font(.system(size: 64, weight: .semibold, design: .rounded))
            .opacity(0.001) // not 0 — SwiftUI may skip rendering at 0
            .frame(width: 1, height: 1)
            .clipped()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .task {
                // Four quick cycles is plenty to flush shader compilation
                // through the GPU. Sleeping a beat between cycles lets
                // each transition settle so we exercise the full
                // animation path, not a single big jump.
                for i in 1...4 {
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    counter = i
                }
            }
    }
}
