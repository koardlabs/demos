import SwiftUI

/// Customer-facing tip entry shown AFTER the sale has been approved in
/// Restaurant / Bar mode. The bill has already been charged for
/// subtotal + tax; the tip the customer picks here is submitted via
/// `tipAdjust` on the just-approved transaction.
///
/// Mirrors the chip layout from `ChargeReviewSheet` so the visual
/// language is consistent, but with a different headline and the option
/// to skip ("No tip") which short-circuits the tipAdjust round trip.
struct TipEntrySheet: View {
    let chargedTotalCents: Int
    let subtotalCents: Int
    let isProcessing: Bool
    let tipPresets: [Double]
    let onConfirm: (_ tipCents: Int) -> Void
    let onSkip: () -> Void

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
        switch selection {
        case let .preset(index):
            // Tip is computed against subtotal only (standard restaurant
            // convention — no tipping on tax).
            let percent = presetPercent(at: index)
            return Int((Double(subtotalCents) * percent / 100.0).rounded())
        case let .custom(cents): return cents
        case .none: return 0
        }
    }

    private var newTotalCents: Int { chargedTotalCents + tipCents }

    var body: some View {
        ZStack {
            KoardBackgroundView()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    chargedCard
                    tipChips
                    if isCustomEntryShown {
                        customPad
                    }
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            // Pin the confirm action with a safe-area inset rather than a
            // ZStack overlay so the custom-tip keypad's lower rows can always
            // scroll clear of the button instead of sliding underneath it.
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
            // Default to the middle preset on present, falling back to the
            // first non-zero one if the user zeroed it out.
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

    // MARK: - Header + charged card

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.point.up.left.and.text.fill")
                .font(.system(size: 24))
                .foregroundStyle(.koardGreen)
            Text("Add a tip")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            Text("Your card has been charged for the bill. Pick a tip to add on top.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.top, 6)
    }

    private var chargedCard: some View {
        VStack(spacing: 10) {
            row(label: "Charged", value: MoneyUtils.centsToStringWithCurrency(chargedTotalCents))
            row(label: "Tip", value: MoneyUtils.centsToStringWithCurrency(tipCents),
                valueColor: tipCents > 0 ? .primary : .secondary)
            Divider().padding(.vertical, 2)
            HStack {
                Text("New total")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(MoneyUtils.centsToStringWithCurrency(newTotalCents))
                    .font(.title.weight(.bold))
                    .foregroundStyle(.koardGreen)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: newTotalCents)
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

    // MARK: - Chips + custom pad

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

    // MARK: - Bottom actions

    private var bottomActions: some View {
        VStack(spacing: 10) {
            Button {
                HapticFeedback.success.notificationOccurred(.success)
                if tipCents > 0 {
                    onConfirm(tipCents)
                } else {
                    onSkip()
                }
            } label: {
                HStack(spacing: 10) {
                    if isProcessing { ProgressView().tint(.white) }
                    Text(tipCents > 0
                         ? "Confirm \(MoneyUtils.centsToStringWithCurrency(newTotalCents))"
                         : "Continue without tip")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.koardGreen)
                )
                .shadow(color: Color.koardGreen.opacity(0.4), radius: 14, x: 0, y: 6)
            }
            .disabled(isProcessing)
        }
    }
}

#Preview {
    TipEntrySheet(
        chargedTotalCents: 4600,
        subtotalCents: 4250,
        isProcessing: false,
        tipPresets: [15, 18, 20],
        onConfirm: { _ in },
        onSkip: {}
    )
}
