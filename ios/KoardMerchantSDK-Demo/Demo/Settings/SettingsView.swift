import SwiftUI
import KoardSDK

struct SettingsView: View {
    @Environment(\.colorScheme) private var currentColorScheme
    @State private var viewModel: SettingsViewModel
    @State private var isShowingLocationSheet = false
    /// Tracks whether any decimal-pad field (tax rate, tip presets) is
    /// focused so we can show a "Done" button above the keyboard. The
    /// decimal pad has no return key on iOS, which is exactly the
    /// dismissal trap the user was complaining about.
    @FocusState private var isAnyNumericFieldFocused: Bool

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KoardBackgroundView()

                Form {
                    // Location lives at the TOP — it's the
                    // most-frequently-changed setting in practice and
                    // belongs above the persistent-preferences sections.
                    locationSection
                    appearanceSection
                    Section("Help") {
                        NavigationLink { TapToPayTutorialView() } label: {
                            Label("Tap to Pay guide", systemImage: "wave.3.right")
                        }
                        .accessibilityIdentifier("settings.tutorial")
                    }
                    checkoutModeSection
                    taxSection
                    tipSection
                    surchargeSection
                    accountLinkingSection
                    accountSection
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    // Keyboard-attached Done button — the only way to
                    // dismiss the decimal pad on iOS without one.
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isAnyNumericFieldFocused = false
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.koardGreen)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear { viewModel.onAppear() }
            .sheet(isPresented: $isShowingLocationSheet) {
                LocationPickerSheet(
                    selectedLocation: viewModel.selectedLocation,
                    availableLocations: viewModel.availableLocations,
                    isLoading: viewModel.isLoadingLocations,
                    onLoad: { await viewModel.fetchLocations() },
                    onSelect: { viewModel.selectLocation($0) }
                )
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var locationSection: some View {
        Section("Location") {
            Button {
                isShowingLocationSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.koardGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.selectedLocation?.name ?? "Choose a location")
                            .font(.body)
                            .foregroundStyle(.primary)
                        if let location = viewModel.selectedLocation {
                            Text("\(location.address.city), \(location.address.state) \(location.address.zip)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No location selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var checkoutModeSection: some View {
        Section {
            Picker("Checkout flow", selection: Binding(
                get: { viewModel.appSettings.checkoutMode },
                set: { viewModel.appSettings.checkoutMode = $0 }
            )) {
                ForEach(AppSettings.CheckoutMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Main View")
        } footer: {
            Text("Retail = type the full amount and charge. Restaurant/Bar = type subtotal, customer adds a tip, then charge. Legacy = the old tax/tip/surcharge form.")
        }
    }

    private var taxSection: some View {
        Section {
            Toggle("Apply tax", isOn: Binding(
                get: { viewModel.appSettings.taxEnabled },
                set: { viewModel.appSettings.taxEnabled = $0 }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .koardGreen))

            if viewModel.appSettings.taxEnabled {
                HStack {
                    Text("Tax rate")
                    Spacer()
                    TextField(
                        "8.25",
                        value: Binding(
                            get: { viewModel.appSettings.taxRatePercent },
                            set: { viewModel.appSettings.taxRatePercent = $0 }
                        ),
                        format: .number.precision(.fractionLength(0...3))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                    .focused($isAnyNumericFieldFocused)
                    Text("%")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Tax")
        }
    }

    private var tipSection: some View {
        Section {
            Toggle("Show tip selection", isOn: Binding(
                get: { viewModel.appSettings.tipEnabled },
                set: { viewModel.appSettings.tipEnabled = $0 }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .koardGreen))

            if viewModel.appSettings.tipEnabled {
                ForEach(0..<3, id: \.self) { index in
                    HStack {
                        Text("Preset \(index + 1)")
                        Spacer()
                        TextField(
                            "0",
                            value: Binding(
                                get: { viewModel.appSettings.tipPresets[index] },
                                set: { newValue in
                                    var presets = viewModel.appSettings.tipPresets
                                    presets[index] = newValue
                                    viewModel.appSettings.tipPresets = presets
                                }
                            ),
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 70)
                        .focused($isAnyNumericFieldFocused)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Tip")
        }
    }

    private var surchargeSection: some View {
        Section {
            Picker("Surcharge policy", selection: Binding(
                get: { viewModel.appSettings.surchargeMode },
                set: { viewModel.appSettings.surchargeMode = $0 }
            )) {
                ForEach(AppSettings.SurchargeMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Text(viewModel.appSettings.surchargeMode.description)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if viewModel.appSettings.surchargeMode == .overridePercent {
                HStack {
                    Text("Override rate")
                    Spacer()
                    TextField(
                        "3.00",
                        value: Binding(
                            get: { viewModel.appSettings.surchargeOverrideRatePercent },
                            set: { viewModel.appSettings.surchargeOverrideRatePercent = $0 }
                        ),
                        format: .number.precision(.fractionLength(0...3))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                    .focused($isAnyNumericFieldFocused)
                    Text("%")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Surcharge")
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            HStack {
                Text("Use device appearance")
                Spacer()
                Toggle("Use device appearance", isOn: Binding(
                    get: { viewModel.appSettings.appearance == .system },
                    set: { viewModel.appSettings.appearance = $0 ? .system : (currentColorScheme == .dark ? .dark : .light) }
                ))
                .labelsHidden()
                .accessibilityIdentifier("settings.systemAppearance")
            }
            HStack {
                Label("Dark mode", systemImage: "moon")
                Spacer()
                Toggle("Dark mode", isOn: Binding(
                    get: { viewModel.appSettings.appearance == .dark || (viewModel.appSettings.appearance == .system && currentColorScheme == .dark) },
                    set: { viewModel.appSettings.appearance = $0 ? .dark : .light }
                ))
                .labelsHidden()
                .accessibilityIdentifier("settings.darkMode")
            }
        }
    }

    private var accountLinkingSection: some View {
        Section {
            if viewModel.needsAccountLinking {
                Button {
                    viewModel.linkAccount()
                } label: {
                    Label("Accept Terms & Link Account", systemImage: "person.badge.key")
                }
            } else {
                HStack {
                    Label("Tap to Pay account", systemImage: "checkmark.seal")
                    Spacer()
                    Text("Linked")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        } header: {
            Text("Tap to Pay")
        } footer: {
            Text(viewModel.needsAccountLinking
                 ? "This device isn't linked to the merchant's Tap to Pay account yet. Accept the terms to link and enable payments."
                 : "This device is linked and ready to accept Tap to Pay payments.")
        }
    }

    private var accountSection: some View {
        Section {
            HStack {
                Text("Environment")
                Spacer()
                Text(viewModel.environmentLabel)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            Button(role: .destructive) {
                viewModel.logout()
            } label: {
                Text("Logout")
            }
        } header: {
            Text("Account")
        } footer: {
            Text("The environment is set at build time by the Xcode scheme you run: UAT or Production. To switch, build or archive with the other scheme.")
        }
    }
}

#Preview {
    SettingsView(
        viewModel: .init(
            koardMerchantService: .mockMerchantService,
            readerState: ReaderStateManager(koardMerchantService: .mockMerchantService),
            onLogout: {}
        )
    )
}
