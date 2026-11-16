import SwiftUI
import KoardSDK

struct RootView: View {
    @State private var isAuthenticated: Bool
    @State private var appSettings = AppSettings.shared
    /// Controls the SwiftUI launch-overlay that bridges from the
    /// storyboard splash into the real UI. Stays true until the
    /// `LaunchOverlay` fires `onDismiss` (after holding the brand
    /// for ~800 ms while we pre-warm Metal shaders behind it).
    @State private var isShowingLaunchOverlay = true

    private let koardMerchantService: KoardMerchantServiceable
    private let readerState: ReaderStateManager

    init(koardMerchantService: KoardMerchantServiceable, readerState: ReaderStateManager) {
        self.koardMerchantService = koardMerchantService
        self.readerState = readerState
        self._isAuthenticated = State(initialValue: koardMerchantService.isAuthenticated)
    }

    var body: some View {
        ZStack {
            // Real app content. Renders BEHIND the launch overlay so by
            // the time the overlay fades, the first paint is already
            // complete and the user lands on a fully-built UI rather
            // than watching it spin up.
            Group {
                if isAuthenticated {
                    MainTabView(
                        koardMerchantService: koardMerchantService,
                        readerState: readerState,
                        onLogout: {
                            readerState.reset()
                            checkAuthenticationStatus()
                        }
                    )
                } else {
                    LoginView(
                        viewModel: .init(
                            koardMerchantService: koardMerchantService,
                            onAuthenticationSuccess: {
                                checkAuthenticationStatus()
                                readerState.ensureReady(force: true)
                            }
                        )
                    )
                }
            }

            // Off-screen, near-invisible — cycles a numericText
            // transition during the launch overlay to compile its
            // Metal shaders before the user's first tap.
            NumericTextShaderWarmup()
                .position(x: -1000, y: -1000)

            // Brand-continuous splash that holds for ~800 ms then
            // fades away. The storyboard launch screen shows the same
            // logo on the same white background, so the visual handoff
            // is seamless.
            if isShowingLaunchOverlay {
                LaunchOverlay {
                    isShowingLaunchOverlay = false
                }
                .transition(.opacity)
                .zIndex(1000)
            }
        }
        .preferredColorScheme(appSettings.appearance.preferredColorScheme)
        .onAppear {
            checkAuthenticationStatus()
        }
    }

    private func checkAuthenticationStatus() {
        let wasAuthenticated = isAuthenticated
        isAuthenticated = koardMerchantService.isAuthenticated
        print("""
        [RootView] Auth status check:
          - Was authenticated: \(wasAuthenticated)
          - Now authenticated: \(isAuthenticated)
        """)
    }
}

#Preview {
    RootView(
        koardMerchantService: .mockMerchantService,
        readerState: ReaderStateManager(koardMerchantService: .mockMerchantService)
    )
}
