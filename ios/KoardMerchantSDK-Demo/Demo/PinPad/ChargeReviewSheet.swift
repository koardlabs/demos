import KoardSDK
import SwiftUI

/// The unified "review your charge" sheet shown after the user taps Charge
/// on the pin pad. Used by both Retail (cashier-facing) and Restaurant /
/// Bar (customer-facing handoff) flows — only the header copy changes.
///
/// Shows: subtotal, tax line (if `AppSettings.taxEnabled`), tip selector
/// (15/18/20% presets + Custom keypad + No tip), live total, big Confirm
/// button. Confirm calls back with the chosen tip in cents; the parent
/// view model handles the actual sale.
struct ChargeReviewSheet: View {
    public enum Style {
        /// Cashier-facing review screen.
        case retail
        /// Customer-facing "handed to you" handoff screen.
        case restaurant
    }

    let style: Style
    let subtotalCents: Int
    let taxCents: Int
    let taxRatePercent: Double
    /// Fixed surcharge rate applied on top of (subtotal + tax + tip), or 0
    /// when the active surcharge mode isn't an override. Sourced from
    /// `AppSettings.surchargeOverrideRatePercent`. Shown as its own line and
    /// folded into the total so the cashier sees exactly what will be charged.
    let surchargeRatePercent: Double
    /// When false, the tip chip / custom pad block is hidden entirely and
    /// `tipCents = 0` is passed through on Confirm. Set false either when
    /// the user disabled tipping in Settings, OR when the active mode is
    /// Restaurant and the tip will be collected after the sale.
    let tipEnabled: Bool
    /// The three preset tip percentages to show as chips. Sourced from
    /// `AppSettings.tipPresets`. Doubles so users can persist 17.5%, etc.
    let tipPresets: [Double]
    /// Optional footnote explaining where the tip will be collected when
    /// the chip block is hidden. Used by Restaurant mode to surface
    /// "Customer will add a tip after the tap" so the cashier knows the
    /// missing tip row isn't an oversight.
    let postSaleTipNote: String?
    let isProcessing: Bool
    /// Called with the chosen tip cents plus which flow (Sale vs Auth)
    /// the cashier picked. Both side-by-side buttons share the same
    /// chosen tip so the customer doesn't have to pick twice.
    let onConfirm: (_ tipCents: Int, _ flow: PinPadViewModel.FlowType) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private enum TipSelection: Hashable {
        case preset(index: Int)
        case custom(cents: Int)
        case none
    }

    @State private var selection: TipSelection = .preset(index: 1)
    @State private var customAmount: PinPadAmount = PinPadAmount()
    @State private var isCustomEntryShown: Bool = false

    private func presetPercent(at index: Int) -> Double {
        tipPresets.indices.contains(index) ? tipPresets[index] : 0
    }

    private var tipCents: Int {
        guard tipEnabled else { return 0 }
        switch selection {
        case let .preset(index):
            // Tip percent is calculated against subtotal only — tax isn't
            // tipped on, which matches restaurant industry convention.
            let percent = presetPercent(at: index)
            return Int((Double(subtotalCents) * percent / 100.0).rounded())
        case let .custom(cents): return cents
        case .none: return 0
        }
    }

    /// Base the override surcharge is computed against. Matches the base
    /// `KoardMerchantService.processSale` uses (subtotal + tax + tip) so the
    /// figure shown here equals what's actually charged.
    private var surchargeBaseCents: Int { subtotalCents + taxCents + tipCents }
    private var surchargeCents: Int {
        guard surchargeRatePercent > 0 else { return 0 }
        return Int((Double(surchargeBaseCents) * surchargeRatePercent / 100.0).rounded())
    }

    private var totalCents: Int { subtotalCents + taxCents + tipCents + surchargeCents }

    private var subtotalString: String { MoneyUtils.centsToStringWithCurrency(subtotalCents) }
    private var taxString: String { MoneyUtils.centsToStringWithCurrency(taxCents) }
    private var tipString: String { MoneyUtils.centsToStringWithCurrency(tipCents) }
    private var surchargeString: String { MoneyUtils.centsToStringWithCurrency(surchargeCents) }
    private var totalString: String { MoneyUtils.centsToStringWithCurrency(totalCents) }

    var body: some View {
        ZStack {
            KoardBackgroundView()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    summaryCard
                    if tipEnabled {
                        tipChips
                        if isCustomEntryShown {
                            customPad
                        }
                    } else if let postSaleTipNote {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.koardGreen)
                            Text(postSaleTipNote)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.koardGreen.opacity(0.08))
                        )
                    }
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            // Pin the Auth/Sale actions with a safe-area inset rather than a
            // ZStack overlay. The inset reserves space at the bottom of the
            // scroll view so the custom-tip keypad's lower rows (7/8/9, 00/0/⌫)
            // can always scroll clear of the buttons instead of sliding
            // underneath them and stealing the taps.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomActions
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color(uiColor: .systemBackground).opacity(colorScheme == .dark ? 0.9 : 0.95)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .onAppear {
            // Default to the middle preset chip on present (or first non-zero
            // preset if the user has zeroed the middle one out).
            let defaultIndex: Int = {
                if presetPercent(at: 1) > 0 { return 1 }
                if presetPercent(at: 0) > 0 { return 0 }
                if presetPercent(at: 2) > 0 { return 2 }
                return 1
            }()
            selection = .preset(index: defaultIndex)
            customAmount.clear()
            isCustomEntryShown = false
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var header: some View {
        switch style {
        case .retail:
            VStack(spacing: 4) {
                Text("Review charge")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Confirm the amount, then hand the device to the customer to tap.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 6)

        case .restaurant:
            VStack(spacing: 6) {
                Image(systemName: "hand.point.up.left.and.text.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.koardGreen)
                Text("Handed to you")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Add a tip to support your service.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 10) {
            row(label: "Subtotal", value: subtotalString)
            if taxCents > 0 {
                row(
                    label: "Tax (\(String(format: "%.2f", taxRatePercent))%)",
                    value: taxString
                )
            }
            row(label: "Tip", value: tipString, valueColor: tipCents > 0 ? .primary : .secondary)
            if surchargeCents > 0 {
                row(
                    label: "Surcharge (\(String(format: "%.2f", surchargeRatePercent))%)",
                    value: surchargeString
                )
            }
            Divider().padding(.vertical, 2)
            HStack {
                Text("Total")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(totalString)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.koardGreen)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: totalCents)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.koardCardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.koardHairline, lineWidth: 0.5)
                )
        )
    }

    private func row(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(valueColor)
        }
    }

    private var tipChips: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    tipChip(
                        label: presetLabel(at: index),
                        subtitle: previewAmount(percent: presetPercent(at: index)),
                        isSelected: isPresetSelected(at: index)
                    ) {
                        isCustomEntryShown = false
                        customAmount.clear()
                        selection = .preset(index: index)
                    }
                }
            }
            HStack(spacing: 10) {
                tipChip(label: "Custom", subtitle: nil, isSelected: isCustomSelected) {
                    isCustomEntryShown = true
                    if case .custom = selection {} else { customAmount.clear() }
                    selection = .custom(cents: customAmount.cents)
                }
                tipChip(label: "No tip", subtitle: nil, isSelected: isNoneSelected) {
                    isCustomEntryShown = false
                    customAmount.clear()
                    selection = .none
                }
            }
        }
    }

    private func presetLabel(at index: Int) -> String {
        let percent = presetPercent(at: index)
        // Drop the trailing ".0" for whole-number percentages so 15.0%
        // reads as "15%". Fractional percentages keep their two decimals.
        if percent == percent.rounded() {
            return "\(Int(percent))%"
        }
        return String(format: "%.2f%%", percent)
    }

    private func isPresetSelected(at index: Int) -> Bool {
        if case let .preset(i) = selection { return i == index }
        return false
    }
    private var isCustomSelected: Bool {
        if case .custom = selection { return true }; return false
    }
    private var isNoneSelected: Bool {
        if case .none = selection { return true }; return false
    }
    private func previewAmount(percent: Double) -> String {
        MoneyUtils.centsToStringWithCurrency(Int((Double(subtotalCents) * percent / 100.0).rounded()))
    }

    private func tipChip(label: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticFeedback.lightImpact.impactOccurred()
            HapticFeedback.lightImpact.prepare()
            action()
        }) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.koardGreen : Color.koardCardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? Color.koardGreen : Color.koardHairline, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var customPad: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Custom tip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(customAmount.formattedDisplay)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: customAmount.cents)
            }
            let columns: [GridItem] = .init(repeating: GridItem(.flexible(), spacing: 10), count: 3)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(1...9, id: \.self) { d in
                    PinPadKeyButton(key: .digit(d)) {
                        customAmount.append(digit: d)
                        selection = .custom(cents: customAmount.cents)
                    }
                }
                PinPadKeyButton(key: .doubleZero) {
                    customAmount.append(digit: 0)
                    customAmount.append(digit: 0)
                    selection = .custom(cents: customAmount.cents)
                }
                PinPadKeyButton(key: .digit(0)) {
                    customAmount.append(digit: 0)
                    selection = .custom(cents: customAmount.cents)
                }
                PinPadKeyButton(key: .backspace) {
                    customAmount.backspace()
                    selection = .custom(cents: customAmount.cents)
                }
            }
        }
    }

    private var bottomActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                actionButton(
                    flow: .preauth,
                    label: "Auth",
                    background: Color(uiColor: .secondarySystemFill),
                    foreground: .primary,
                    border: Color.koardHairline
                )
                actionButton(
                    flow: .sale,
                    label: "Sale",
                    background: Color.koardGreen,
                    foreground: .white,
                    border: Color.koardGreen
                )
            }

            Button("Cancel", action: onCancel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func actionButton(
        flow: PinPadViewModel.FlowType,
        label: String,
        background: Color,
        foreground: Color,
        border: Color
    ) -> some View {
        Button {
            HapticFeedback.success.notificationOccurred(.success)
            onConfirm(tipCents, flow)
        } label: {
            HStack(spacing: 8) {
                if isProcessing { ProgressView().tint(foreground) }
                VStack(spacing: 2) {
                    Text(label)
                        .font(.headline)
                    Text(totalString)
                        .font(.footnote.weight(.semibold))
                        .opacity(0.9)
                }
                .foregroundStyle(foreground)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(border, lineWidth: 1)
                    )
            )
            .shadow(
                color: (flow == .sale ? Color.koardGreen : .black).opacity(0.25),
                radius: 10, x: 0, y: 4
            )
        }
        .disabled(isProcessing || totalCents <= 0)
    }
}

#Preview("Retail (tip on review)") {
    ChargeReviewSheet(
        style: .retail,
        subtotalCents: 4250,
        taxCents: 350,
        taxRatePercent: 8.25,
        surchargeRatePercent: 3.0,
        tipEnabled: true,
        tipPresets: [15, 18, 20],
        postSaleTipNote: nil,
        isProcessing: false,
        onConfirm: { _, _ in },
        onCancel: {}
    )
}

#Preview("Restaurant (tip after tap)") {
    ChargeReviewSheet(
        style: .restaurant,
        subtotalCents: 4250,
        taxCents: 350,
        taxRatePercent: 8.25,
        surchargeRatePercent: 3.0,
        tipEnabled: false,
        tipPresets: [15, 18, 20],
        postSaleTipNote: "Customer will be asked for a tip after they tap.",
        isProcessing: false,
        onConfirm: { _, _ in },
        onCancel: {}
    )
}

#Preview("Tip disabled") {
    ChargeReviewSheet(
        style: .retail,
        subtotalCents: 4250,
        taxCents: 350,
        taxRatePercent: 8.25,
        surchargeRatePercent: 0,
        tipEnabled: false,
        tipPresets: [15, 18, 20],
        postSaleTipNote: nil,
        isProcessing: false,
        onConfirm: { _, _ in },
        onCancel: {}
    )
}
