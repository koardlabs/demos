import SwiftUI
import KoardSDK

struct MainTabView: View {
    let koardMerchantService: KoardMerchantServiceable
    let readerState: ReaderStateManager
    let onLogout: () -> Void

    @State private var selectedTab: Int = 1
    @State private var appSettings = AppSettings.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            TransactionHistoryView(
                viewModel: .init(koardMerchantService: koardMerchantService)
            )
            .tabItem {
                Image(systemName: "receipt")
                Text("Activity")
            }
            .tag(0)

            NavigationStack {
                checkoutTab
            }
            .tabItem {
                Image(systemName: "square.grid.2x2")
                Text("Register")
            }
            .tag(1)

            SettingsView(
                viewModel: .init(
                    koardMerchantService: koardMerchantService,
                    readerState: readerState,
                    onLogout: onLogout
                )
            )
            .tabItem {
                Image(systemName: "gearshape")
                Text("Settings")
            }
            .tag(2)
        }
        .modifier(POSNavigationStyle())
        .tint(.koardGreen)
    }

    /// The checkout tab swaps between the new pin-pad flows and the legacy
    /// form view based on the persisted Main View preference.
    @ViewBuilder
    private var checkoutTab: some View {
        switch appSettings.checkoutMode {
        case .retail, .restaurantBar:
            PinPadView(
                viewModel: .init(
                    koardMerchantService: koardMerchantService,
                    readerState: readerState
                )
            )
        case .legacy:
            TransactionView(
                viewModel: .init(koardMerchantService: koardMerchantService)
            )
        }
    }
}

#Preview {
    MainTabView(
        koardMerchantService: .mockMerchantService,
        readerState: ReaderStateManager(koardMerchantService: .mockMerchantService),
        onLogout: {}
    )
}
