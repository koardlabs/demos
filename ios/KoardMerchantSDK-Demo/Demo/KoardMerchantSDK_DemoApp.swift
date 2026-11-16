import KoardSDK
import SwiftUI

@main
struct KoardMerchantSDK_DemoApp: App {
    private let koardMerchantService: KoardMerchantServiceable
    private let readerState: ReaderStateManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UISegmentedControl.appearance().selectedSegmentTintColor = .koardGreen
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.koardGreen], for: .normal)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance

        // Pre-warm the cached currency formatter and asset cache so the
        // first keystroke on the pin pad doesn't pay the cold-start cost.
        // NumberFormatter's first allocation on iOS takes ~3-5 ms; doing
        // it here at app init means the first amount render is instant.
        Self.preWarmFirstLaunchHotPaths()

        if POSPreviewLaunch.enabled {
            let service = MockKoardMerchantService()
            self.koardMerchantService = service
            self.readerState = ReaderStateManager(koardMerchantService: service)
            return
        }

        guard let config = ConfigurationManager.loadConfiguration() else {
            fatalError("Failed to load configuration. Please ensure Config.plist exists and contains valid credentials.")
        }

        let service = KoardMerchantService(
            apiKey: config.apiKey,
            environment: config.environment
        )
        self.koardMerchantService = service

        // Initialize SDK immediately so it can read persisted auth token from Keychain
        service.setup()

        // iOS Keychain items survive app uninstall by design — Apple
        // intentionally keeps them so password-manager apps can hand
        // credentials back to a freshly-installed app. For us that
        // meant uninstalling the demo and reinstalling left the user
        // silently "logged in" with a stale session.
        //
        // Detect a fresh install via a UserDefaults sentinel
        // (UserDefaults IS cleared on uninstall) and wipe the SDK's
        // keychain state if the flag is missing. After clearing we set
        // the flag so subsequent launches don't keep clearing it.
        Self.clearStaleSessionIfFirstLaunch(service: service)

        // Build the reader state machine BEFORE we hand a view tree off so
        // the pin-pad view can observe `.preparing` from the very first frame
        // instead of seeing `.idle` and racing the prepare task.
        self.readerState = ReaderStateManager(koardMerchantService: service)

        // Fire prepare on launch. We don't await — the screen will reflect
        // the current state via `readerState.state`.
        readerState.ensureReady(force: true)
    }

    var body: some Scene {
        WindowGroup {
            if POSPreviewLaunch.login {
                LoginView(viewModel: .init(koardMerchantService: koardMerchantService, onAuthenticationSuccess: {}))
            } else {
                RootView(koardMerchantService: koardMerchantService, readerState: readerState)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard !POSPreviewLaunch.enabled else { return }
            switch newPhase {
            case .active:
                print("[App] became active — checking reader freshness")
                // Re-prepare if we've been backgrounded for a while or last
                // attempt failed. The manager itself decides whether to do
                // anything based on staleness.
                readerState.handleAppDidBecomeActive()
            case .background:
                print("[App] entered background")
            case .inactive:
                print("[App] became inactive")
            @unknown default:
                break
            }
        }
    }

    /// Touches the hot paths the pin pad will hit on the user's very
    /// first keystroke, so the cost of those first-time allocations is
    /// paid here at launch — before the keypad is even visible — instead
    /// of inline with the user's tap.
    ///
    /// Specifically:
    /// - `PinPadAmount().formattedDisplay` forces the cached
    ///   `NumberFormatter` static to initialize.
    /// - Resolving the asset-catalog colors and the logo image warms the
    ///   `UIImage` / `UIColor` lookup cache.
    private static let hasLaunchedBeforeKey = "demo.hasLaunchedBefore"

    private static func clearStaleSessionIfFirstLaunch(service: KoardMerchantServiceable) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: hasLaunchedBeforeKey) else { return }
        // First-ever launch (or first launch after install). Nuke any
        // surviving keychain items so the user starts on a clean login
        // screen instead of a stale logged-in state.
        service.logout()
        defaults.set(true, forKey: hasLaunchedBeforeKey)
        print("[App] First launch after install — cleared stale Keychain session.")
    }

    private static func preWarmFirstLaunchHotPaths() {
        var amount = PinPadAmount()
        amount.append(digit: 1)
        _ = amount.formattedDisplay
        _ = UIColor.koardGreen
        _ = UIColor(named: "KoardCardSurface")
        _ = UIImage(named: "koardLogo")
        // Spin up the haptic engine so the first tap on the pin pad
        // doesn't pay the "fresh generator" wake-up cost.
        HapticFeedback.preWarm()
    }
}
