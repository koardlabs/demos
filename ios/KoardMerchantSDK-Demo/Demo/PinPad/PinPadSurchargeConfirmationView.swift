import KoardSDK
import SwiftUI

/// Customer-facing surcharge confirmation surfaced from the pin-pad flows.
///
/// The legacy `TransactionView` has its own (richer) surcharge sheet that
/// also lets the merchant override the surcharge. The pin-pad flows are
/// simpler — they only need Accept / Decline because the cashier shouldn't
/// be editing a customer-facing surcharge mid-handoff.
struct PinPadSurchargeConfirmationView: View {
    let prompt: PinPadViewModel.SurchargePrompt
    let isProcessing: Bool
    let onDecision: (Bool) -> Void

    private var currency: CurrencyCode {
        CurrencyCode(currencyCode: prompt.currency, displayName: nil)
    }

    private func formatted(_ cents: Int) -> String {
        MoneyUtils.centsToStringWithCurrency(cents, currency: currency)
    }

    var body: some View {
        ZStack {
            KoardBackgroundView()

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.orange)

                Text("Surcharge Notice")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                Text(prompt.disclosure)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)

                VStack(spacing: 10) {
                    surchargeRow(title: "Base amount", value: formatted(prompt.baseAmountCents))
                    surchargeRow(title: "Surcharge", value: formatted(prompt.surchargeAmountCents))
                    Divider()
                    surchargeRow(title: "Total", value: formatted(prompt.totalCents), bold: true)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.koardCardSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.koardHairline, lineWidth: 0.5)
                        )
                )

                Spacer()

                Button {
                    onDecision(true)
                } label: {
                    HStack(spacing: 10) {
                        if isProcessing { ProgressView().tint(.white) }
                        Text("Accept & Pay \(formatted(prompt.totalCents))")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Color.koardGreen)
                    )
                    .shadow(color: Color.koardGreen.opacity(0.4), radius: 18, x: 0, y: 6)
                }
                .disabled(isProcessing)

                Button("Decline") {
                    onDecision(false)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 22)
            .padding(.top, 30)
            .padding(.bottom, 16)
        }
    }

    private func surchargeRow(title: String, value: String, bold: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(bold ? .semibold : .regular))
                .foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(bold ? .bold : .medium))
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    PinPadSurchargeConfirmationView(
        prompt: .init(
            transactionId: "tx_demo",
            disclosure: "A 3.00% surcharge is applied to cover card processing fees. Do you accept?",
            baseAmountCents: 4250,
            surchargeAmountCents: 128,
            currency: "USD"
        ),
        isProcessing: false,
        onDecision: { _ in }
    )
}
