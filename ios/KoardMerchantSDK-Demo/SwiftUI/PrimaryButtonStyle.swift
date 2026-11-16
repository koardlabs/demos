import SwiftUI

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle {
        PrimaryButtonStyle()
    }

    /// Compact variant used in toolbars and small cards.
    static var primaryCompact: PrimaryButtonStyle {
        PrimaryButtonStyle(compact: true)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ContentView(compact: compact, configuration: configuration)
    }

    private struct ContentView: View {
        @Environment(\.isEnabled) private var isEnabled: Bool
        let compact: Bool
        let configuration: Configuration

        private var backgroundColor: Color {
            switch (isEnabled, configuration.isPressed) {
            case (false, _):
                return .koardGreen.opacity(0.35)
            case (true, true):
                return .koardGreen.opacity(0.85)
            case (true, false):
                return .koardGreen
            }
        }

        var body: some View {
            configuration
                .label
                .font(compact ? .subheadline.weight(.semibold) : .headline)
                .foregroundColor(.white)
                .padding(.horizontal, compact ? 18 : 24)
                .padding(.vertical, compact ? 9 : 14)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

#Preview("Default State") {
    Button {
    } label: {
        Text("Primary Button")
    }
    .buttonStyle(.primary)
}


#Preview("Disabled State") {
    Button {
    } label: {
        Text("Primary Button")
    }
    .buttonStyle(.primary)
    .disabled(true)
}
