import KoardSDK
import SwiftUI

/// A register and editable ticket backed by the existing checkout lifecycle.
struct PinPadView: View {
    @State private var viewModel: PinPadViewModel
    @State private var appSettings = AppSettings.shared
    @State private var showsLocations = false

    init(viewModel: PinPadViewModel) { self.viewModel = viewModel }

    var body: some View {
        VStack(spacing: 0) {
            registerHeader
            statusLine.padding(.horizontal, 18).background(POSDesign.surface)
            Divider()
            POSRegisterWorkspace(
                subtotalCents: viewModel.amount.cents,
                onSubtotalChange: { viewModel.setSubtotalCents($0) },
                onCheckout: { viewModel.chargeButtonTapped(mode: appSettings.checkoutMode) },
                isProcessing: viewModel.isProcessing || viewModel.sheet != nil,
                taxCents: appSettings.taxCents(forSubtotalCents: viewModel.amount.cents)
            )
        }
        .background(POSDesign.background)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            viewModel.readerState.ensureReady()
            await viewModel.refreshActiveLocation()
        }
        .sheet(isPresented: $showsLocations) {
            LocationPickerSheet(
                selectedLocation: viewModel.selectedLocation,
                availableLocations: viewModel.availableLocations,
                isLoading: viewModel.isLoadingLocations,
                onLoad: { await viewModel.fetchLocations() },
                onSelect: { viewModel.selectLocation($0) }
            )
        }
        .sheet(item: $viewModel.sheet) { sheet in
            Group {
                switch sheet {
                case let .review(context):
                    // Chip block visible only if tipping is on in Settings
                    // AND this review collects the tip up front (retail).
                    // Restaurant gets the post-tap-tip footnote instead.
                    let showsTipChips = context.collectsTipUpFront && appSettings.tipEnabled
                    let postSaleNote: String? = {
                        if !showsTipChips,
                           context.style == .restaurant,
                           appSettings.tipEnabled {
                            return "Customer will be asked for a tip after the tap."
                        }
                        return nil
                    }()
                    ChargeReviewSheet(
                        style: context.style,
                        subtotalCents: context.subtotalCents,
                        taxCents: context.taxCents,
                        taxRatePercent: context.taxRatePercent,
                        surchargeRatePercent: context.surchargeRatePercent,
                        tipEnabled: showsTipChips,
                        tipPresets: appSettings.tipPresets,
                        postSaleTipNote: postSaleNote,
                        isProcessing: viewModel.isProcessing,
                        onConfirm: { tip, flow in
                            viewModel.reviewConfirmed(tipCents: tip, flow: flow)
                        },
                        onCancel: { viewModel.reviewCancelled() }
                    )
                case let .result(result):
                    SaleResultSheet(
                        result: result,
                        onDone: { viewModel.resultSheetDismissed() },
                        onContinuePartial: viewModel.partialApprovalRemainder != nil
                            ? { viewModel.continuePartialApproval() }
                            : nil
                    )
                case let .tipEntry(context):
                    TipEntrySheet(
                        chargedTotalCents: context.chargedTotalCents,
                        subtotalCents: context.subtotalCents,
                        isProcessing: viewModel.isProcessing,
                        tipPresets: appSettings.tipPresets,
                        onConfirm: { tip in
                            Task { await viewModel.tipEntryConfirmed(tipCents: tip) }
                        },
                        onSkip: { viewModel.tipEntrySkipped() }
                    )
                case let .surcharge(prompt):
                    PinPadSurchargeConfirmationView(
                        prompt: prompt,
                        isProcessing: viewModel.isProcessing,
                        onDecision: { decision in
                            Task { await viewModel.handleSurchargeDecision(confirm: decision) }
                        }
                    )
                case .preparingReader:
                    ReaderPreparingModal(
                        readerState: viewModel.readerState,
                        onReady: { viewModel.preparingModalReady() },
                        onDismiss: { viewModel.preparingModalDismissed() }
                    )
                }
            }
            // The pre-charge review sheet can be swiped down to dismiss
            // (same as tapping Cancel — nothing has been charged yet).
            // Every other case is mid-transaction and must be committed via
            // its own explicit Done / Accept / Decline button, so it stays
            // locked against an accidental swipe-away.
            .interactiveDismissDisabled(!sheet.allowsInteractiveDismiss)
        }
    }

    private var registerHeader: some View {
        HStack(spacing: 16) {
            Text("koard")
                .font(.system(size: 25, weight: .bold))
                .tracking(-1)
                .foregroundStyle(POSDesign.ink)
            Rectangle().fill(POSDesign.line).frame(width: 1, height: 28)
            Button { showsLocations = true } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.selectedLocation?.name ?? "Choose location")
                            .font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(appSettings.checkoutMode.displayName)
                            .font(.caption).foregroundStyle(POSDesign.muted)
                    }
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .foregroundStyle(POSDesign.ink)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isProcessing || viewModel.sheet != nil)
            .accessibilityIdentifier("pos.location")
            Spacer(minLength: 0)
            if POSPreviewLaunch.enabled {
                Text("PREVIEW").font(.system(size: 9, weight: .bold)).tracking(1)
                    .foregroundStyle(POSDesign.muted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(POSDesign.surface)
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            // Important: the status line — which reads `.progress` — lives in
            // its own `ReaderStatusText` subview so progress ticks during
            // prepare re-render only that label, not this body / the keypad.
            ReaderStatusText(readerState: viewModel.readerState)
                .truncationMode(.tail)
            Spacer()
            if viewModel.readerState.needsAccountLinking {
                // prepare() reported the Tap to Pay account isn't linked. The
                // merchant links on their terms by accepting T&C here (calls
                // linkAccount() then re-prepares) — we never auto-prompt.
                Button("Accept T&C") {
                    viewModel.readerState.linkAccount()
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.koardGreen)
            } else if viewModel.readerState.state.isFailed {
                Button("Retry") {
                    viewModel.readerState.ensureReady(force: true)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.koardGreen)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        if viewModel.readerState.needsAccountLinking { return .orange }
        switch viewModel.readerState.state {
        case .ready: return .koardGreen
        case .preparing: return .orange
        case .failed: return .red
        case .unsupported: return .red.opacity(0.7)
        case .idle: return Color(uiColor: .systemGray3)
        }
    }

    /// Isolates the reader status line — including the live prepare `progress`
    /// percentage — into its own view. Because only this view reads
    /// `readerState.progress`, the frequent progress ticks during prepare
    /// re-render just this label, not the whole `PinPadView` body / keypad.
    private struct ReaderStatusText: View {
        let readerState: ReaderStateManager

        var body: some View {
            Text(readerState.needsAccountLinking ? "Account not linked" : inlineStatus)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        /// While preparing, shows the live `\(progress)%` from the reader's
        /// update events so the pin-pad header reflects readiness in real time.
        private var inlineStatus: String {
            switch readerState.state {
            case .idle: return "Card reader idle"
            case .preparing:
                let percent = readerState.progress
                return percent > 0 ? "Preparing card reader… \(percent)%" : "Preparing card reader…"
            case .ready: return "Card reader ready"
            case .unsupported: return "Tap to Pay not supported on this device"
            case let .failed(message): return "Card reader unavailable: \(message)"
            }
        }
    }

 }

#Preview {
    PinPadView(viewModel: .init(
        koardMerchantService: .mockMerchantService,
        readerState: ReaderStateManager(koardMerchantService: .mockMerchantService)
    ))
}
