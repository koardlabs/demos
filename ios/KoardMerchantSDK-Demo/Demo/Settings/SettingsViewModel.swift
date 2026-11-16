import Foundation
import KoardSDK

@MainActor
@Observable
public final class SettingsViewModel {
    public private(set) var selectedLocation: Location?
    public private(set) var availableLocations: [Location] = []
    public private(set) var isLoadingLocations: Bool = false

    /// We keep a handle to the AppSettings singleton so SettingsView can
    /// bind directly to it without re-implementing toggle plumbing.
    public let appSettings: AppSettings = .shared

    @ObservationIgnored private let koardMerchantService: KoardMerchantServiceable
    @ObservationIgnored private let readerState: ReaderStateManager
    @ObservationIgnored public var onLogout: () -> Void

    public var environmentLabel: String {
        // Pull the same canonical env key ConfigurationManager resolved at
        // launch so this label reflects the section we actually loaded.
        ConfigurationManager.resolveEnvKey()
    }

    init(
        koardMerchantService: KoardMerchantServiceable,
        readerState: ReaderStateManager,
        onLogout: @escaping () -> Void
    ) {
        self.koardMerchantService = koardMerchantService
        self.readerState = readerState
        self.onLogout = onLogout
        self.selectedLocation = koardMerchantService.activeLocation
    }

    public func onAppear() {
        selectedLocation = koardMerchantService.activeLocation
        Task { [weak self] in
            guard let self else { return }
            if let refreshed = await self.koardMerchantService.loadActiveLocation() {
                self.selectedLocation = refreshed
            }
        }
    }

    public func fetchLocations() async {
        availableLocations = []
        isLoadingLocations = true
        defer { isLoadingLocations = false }
        do {
            let refreshed = try await koardMerchantService.fetchLocations()
            try Task.checkCancellation()
            availableLocations = refreshed
        } catch {
            print("[SettingsViewModel] failed to fetch locations: \(error)")
        }
    }

    public func selectLocation(_ location: Location) {
        koardMerchantService.updateLocation(location: location)
        selectedLocation = location
        // `updateLocation` tears down the old reader session and re-prepares
        // internally. Tell the reader state machine so the checkout view
        // shows "Preparing card reader" during the recovery instead of the
        // stale "Card reader unavailable" error.
        readerState.noteLocationChanged()
    }

    public func logout() {
        koardMerchantService.logout()
        onLogout()
    }

    /// True when the Tap to Pay account still needs to be linked. Reads through
    /// to the reader state machine (observed live by SwiftUI).
    public var needsAccountLinking: Bool {
        readerState.needsAccountLinking
    }

    /// Link the merchant's Tap to Pay account (accept T&C + link), then prepare.
    public func linkAccount() {
        readerState.linkAccount()
    }
}
