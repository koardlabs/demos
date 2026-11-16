import SwiftUI

enum POSPreviewLaunch {
    static var enabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("-pos-preview")
            || ProcessInfo.processInfo.arguments.contains("-pos-login-preview")
        #else
        return false
        #endif
    }

    static var login: Bool {
        enabled && ProcessInfo.processInfo.arguments.contains("-pos-login-preview")
    }
}

enum POSDesign {
    static let ink = Color.primary
    static let background = Color.extraLightGray
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .koardLightGray : .white })
    static let muted = Color.koardDarkGray
    static let line = Color(uiColor: .separator).opacity(0.3)

    static func accent(for category: POSCategory) -> Color { .koardGreen }

}

struct POSButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : POSDesign.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(prominent ? Color.koardGreen : POSDesign.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(POSDesign.line, lineWidth: prominent ? 0 : 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

struct POSNavigationStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) { content.tabViewStyle(.sidebarAdaptable) }
        else { content }
    }
}
