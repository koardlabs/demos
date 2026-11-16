import UIKit

/// Shared, pre-prepared `UIImpactFeedbackGenerator` instances.
///
/// Allocating a new generator on every tap is a textbook cold-start
/// lag: the first call to a fresh generator includes the haptic engine
/// warm-up (Apple's docs explicitly call this out — see "Preparing the
/// Generator"). Keeping a single instance alive and calling `prepare()`
/// keeps the engine ready for instant playback.
///
/// All sites that want haptic feedback should use these globals instead
/// of constructing their own `UIImpactFeedbackGenerator(...)`.
enum HapticFeedback {
    static let lightImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()

    static let success: UINotificationFeedbackGenerator = {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        return g
    }()

    /// Called from the app's pre-warm hook so the haptic engine is
    /// spun up before the user can even reach the pin pad.
    static func preWarm() {
        lightImpact.prepare()
        success.prepare()
    }
}
