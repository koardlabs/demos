import SwiftUI

/// Logical key on the pin-pad. Maps directly to a button on screen.
public enum PinPadKey: Hashable, Identifiable {
    case digit(Int)
    case doubleZero
    case backspace

    public var id: String {
        switch self {
        case let .digit(d): return "d\(d)"
        case .doubleZero: return "00"
        case .backspace: return "del"
        }
    }

    public var title: String {
        switch self {
        case let .digit(d): return "\(d)"
        case .doubleZero: return "00"
        case .backspace: return ""
        }
    }

    public var systemImage: String? {
        switch self {
        case .backspace: return "delete.left"
        default: return nil
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case let .digit(d): return "Digit \(d)"
        case .doubleZero: return "Double zero"
        case .backspace: return "Backspace"
        }
    }
}

/// A single circular pad button. Designed to look like a 2026 POS — soft
/// rounded surface, light press animation, dynamic colors that work in both
/// light and dark mode.
struct PinPadKeyButton: View {
    let key: PinPadKey
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            // Use the shared, pre-prepared haptic generator. Allocating
            // a new UIImpactFeedbackGenerator on every tap is the
            // textbook cold-start lag — the first call to a fresh
            // generator includes the haptic engine warm-up. The shared
            // generator is `prepare()`-d at app launch so the first tap
            // is as fast as every subsequent one.
            HapticFeedback.lightImpact.impactOccurred()
            // Tell the system we expect more taps so it keeps the haptic
            // engine warm for the next one.
            HapticFeedback.lightImpact.prepare()
            action()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.koardKeySurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.koardHairline, lineWidth: 0.5)
                    )

                if let systemImage = key.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.primary)
                } else {
                    Text(key.title)
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            .frame(height: 70)
            .accessibilityLabel(key.accessibilityLabel)
        }
        .buttonStyle(PinPadKeyButtonStyle())
    }
}

private struct PinPadKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
