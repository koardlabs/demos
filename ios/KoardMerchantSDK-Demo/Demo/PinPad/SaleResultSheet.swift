import KoardSDK
import SwiftUI

/// Dismissable sheet shown after a sale completes (approved, declined,
/// cancelled, or error). Replaces the old popover-based summary and now
/// surfaces the full receipt details — approval code, processor codes,
/// processor response message, gateway response message — so the demo
/// matches what an integrator would actually show on a receipt.
struct SaleResultSheet: View {
    public enum Outcome: Equatable {
        /// Sale is in flight against the gateway. The sheet pops up the
        /// moment the user confirms so they always have visible feedback
        /// while the network call is happening, and transitions in-place
        /// to one of the settled outcomes below when the response comes
        /// back.
        case processing
        case approved
        /// Issuer authorized strictly less than what we asked for. The
        /// sheet shows what was authorized + a "Tap for remaining $X"
        /// action that fires another charge for the leftover amount.
        case partiallyApproved
        case declined
        case cancelled
        /// Gateway returned `.pending` — the transaction was accepted but
        /// not finalized. The cashier can check History → Detail later
        /// for the eventual settled state.
        case pending
        case error

        public var isSettled: Bool {
            switch self {
            case .processing: return false
            case .approved, .partiallyApproved, .declined, .cancelled, .pending, .error: return true
            }
        }
    }

    public struct ResultData: Equatable {
        public let outcome: Outcome
        public let title: String
        public let total: String
        /// When the issuer partially approved, this is the leftover
        /// amount as a formatted currency string ("$26.00"). nil for
        /// everything else.
        public let remainingAmount: String?
        public let subtotal: String?
        public let tax: String?
        public let tip: String?
        public let surcharge: String?
        /// Surcharge percentage (e.g. 3.0 for 3%) when the gateway returned
        /// one. Used to render the breakdown row as "Surcharge (3%)" so
        /// the cashier / customer can see how the surcharge was computed.
        public let surchargeRate: Double?
        public let card: String?
        public let cardBrand: String?
        public let transactionId: String?
        public let status: String
        public let statusReason: String?
        /// Processor / gateway receipt fields. All optional — only rendered
        /// when present so a `.cancelled` or `.error` outcome with no
        /// upstream response doesn't show empty rows.
        public let approvalCode: String?
        public let processorResponseCode: String?
        public let processorResponseMessage: String?
        public let gatewayResponseMessage: String?

        public init(
            outcome: Outcome,
            title: String,
            total: String,
            remainingAmount: String? = nil,
            subtotal: String?,
            tax: String?,
            tip: String?,
            surcharge: String?,
            surchargeRate: Double? = nil,
            card: String?,
            cardBrand: String?,
            transactionId: String?,
            status: String,
            statusReason: String?,
            approvalCode: String? = nil,
            processorResponseCode: String? = nil,
            processorResponseMessage: String? = nil,
            gatewayResponseMessage: String? = nil
        ) {
            self.outcome = outcome
            self.title = title
            self.total = total
            self.remainingAmount = remainingAmount
            self.subtotal = subtotal
            self.tax = tax
            self.tip = tip
            self.surcharge = surcharge
            self.surchargeRate = surchargeRate
            self.card = card
            self.cardBrand = cardBrand
            self.transactionId = transactionId
            self.status = status
            self.statusReason = statusReason
            self.approvalCode = approvalCode
            self.processorResponseCode = processorResponseCode
            self.processorResponseMessage = processorResponseMessage
            self.gatewayResponseMessage = gatewayResponseMessage
        }
    }

    let result: ResultData
    let onDone: () -> Void
    /// When non-nil and outcome is .partiallyApproved, a "Tap for
    /// remaining $X" button is rendered. Triggers another charge for
    /// the remaining amount via the parent view model.
    var onContinuePartial: (() -> Void)? = nil

    var body: some View {
        ZStack {
            KoardBackgroundView()

            ScrollView {
                VStack(spacing: 18) {
                    headline
                    totalCard
                    if result.outcome.isSettled {
                        // Breakdown + receipt details only make sense once
                        // we have an actual response from the gateway.
                        if result.outcome == .partiallyApproved {
                            partialApprovalBanner
                        }
                        breakdownCard
                        receiptDetailsCard
                        if let txId = result.transactionId, !txId.isEmpty {
                            idCard(transactionId: txId)
                        }
                    }
                    actions
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 40)
                .animation(.easeInOut(duration: 0.25), value: result.outcome)
            }
        }
    }

    // MARK: - Headline + outcome glyph

    private var headline: some View {
        VStack(spacing: 10) {
            outcomeGlyph
                .frame(height: 70)
            Text(result.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            Text(result.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let reason = result.statusReason, !reason.isEmpty, reason != result.status {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var outcomeGlyph: some View {
        switch result.outcome {
        case .processing:
            // Tinted activity ring — matches the preparing modal's
            // visual language so the user has continuity from "reader
            // preparing" through "sale processing" to "sale complete".
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.koardGreen)
                .scaleEffect(1.8)
        case .approved:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.koardGreen)
        case .partiallyApproved:
            Image(systemName: "checkmark.circle.badge.questionmark.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
        case .declined:
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "slash.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color(uiColor: .systemGray))
        case .pending:
            // Clock + blue tint. Same intent as Apple's "in progress"
            // system iconography — visually distinct from approved /
            // declined / error so the cashier doesn't misread it.
            Image(systemName: "clock.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color(uiColor: .systemBlue))
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Total + card brand

    private var totalCard: some View {
        VStack(spacing: 8) {
            Text(result.outcome == .processing ? "Charging" : "Total")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(result.total)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            if let cardBrand = result.cardBrand, let card = result.card, !card.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard.fill")
                        .foregroundStyle(.secondary)
                    Text("\(cardBrand) · \(card)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .padding(.top, 4)
            } else if let card = result.card, !card.isEmpty {
                Text(card)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.koardCardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.koardHairline, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Breakdown

    @ViewBuilder
    private var breakdownCard: some View {
        if hasBreakdown {
            VStack(spacing: 10) {
                Text("Breakdown")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let subtotal = result.subtotal { row("Subtotal", subtotal) }
                if let tax = result.tax { row("Tax", tax) }
                if let tip = result.tip { row("Tip", tip) }
                if let surcharge = result.surcharge {
                    row(surchargeLabel, surcharge)
                }
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
        }
    }

    private var hasBreakdown: Bool {
        result.subtotal != nil || result.tax != nil || result.tip != nil || result.surcharge != nil
    }

    /// Highlighted banner that surfaces the remaining-balance amount on
    /// partial approvals. Rendered as a separate card so it doesn't get
    /// lost in the breakdown rows.
    @ViewBuilder
    private var partialApprovalBanner: some View {
        if let remaining = result.remainingAmount {
            HStack(spacing: 12) {
                Image(systemName: "creditcard.and.123")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remaining balance")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(remaining)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.orange.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                    )
            )
        }
    }

    /// "Surcharge (3%)" when we have the rate, "Surcharge" otherwise.
    /// Drops the trailing ".00" so 3% reads as `3%` not `3.00%`.
    private var surchargeLabel: String {
        guard let rate = result.surchargeRate, rate > 0 else { return "Surcharge" }
        let formatted: String = (rate == rate.rounded())
            ? "\(Int(rate))%"
            : String(format: "%.2f%%", rate)
        return "Surcharge (\(formatted))"
    }

    // MARK: - Receipt details (approval code, processor codes, messages)

    @ViewBuilder
    private var receiptDetailsCard: some View {
        if hasReceiptDetails {
            VStack(spacing: 10) {
                Text("Receipt details")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let approvalCode = result.approvalCode, !approvalCode.isEmpty {
                    row("Approval code", approvalCode, monospaced: true)
                }
                if let code = result.processorResponseCode, !code.isEmpty {
                    row("Processor code", code, monospaced: true)
                }
                if let message = result.processorResponseMessage, !message.isEmpty {
                    row("Processor message", message)
                }
                if let gateway = result.gatewayResponseMessage,
                   !gateway.isEmpty,
                   gateway != result.processorResponseMessage {
                    row("Gateway message", gateway)
                }
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
        }
    }

    private var hasReceiptDetails: Bool {
        [result.approvalCode,
         result.processorResponseCode,
         result.processorResponseMessage,
         result.gatewayResponseMessage]
            .contains { $0?.isEmpty == false }
    }

    // MARK: - Row builder

    private func row(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced ? .system(.subheadline, design: .monospaced).weight(.medium)
                                 : .subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func idCard(transactionId: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Transaction ID")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(transactionId)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.koardCardSurface.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.koardHairline, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        switch result.outcome {
        case .processing:
            // Intentionally no Done button while in flight — the user
            // must wait for a settled outcome. Sheet is also marked
            // .interactiveDismissDisabled(true) in PinPadView so a
            // swipe-down can't dismiss either.
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.secondary)
                Text("Please don't close the app")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .approved, .partiallyApproved, .declined, .cancelled, .pending, .error:
            VStack(spacing: 10) {
                if result.outcome == .partiallyApproved,
                   let onContinuePartial,
                   let remaining = result.remainingAmount {
                    // Primary action for partial approvals — feed the
                    // remainder back through the charge pipeline so the
                    // customer can tap another card. Sits ABOVE Done so
                    // it's the obvious next step.
                    Button {
                        onContinuePartial()
                    } label: {
                        Text("Tap for remaining \(remaining)")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(Color.orange)
                            )
                            .shadow(color: Color.orange.opacity(0.4), radius: 12, x: 0, y: 4)
                    }
                }
                Button(action: onDone) {
                    Text(result.outcome == .partiallyApproved ? "Stop here" : "Done")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.koardGreen)
                        )
                        .shadow(color: Color.koardGreen.opacity(0.35), radius: 12, x: 0, y: 4)
                }
            }
        }
    }
}

#Preview("Approved") {
    SaleResultSheet(
        result: .init(
            outcome: .approved,
            title: "Approved",
            total: "$46.00",
            subtotal: "$42.50",
            tax: "$3.50",
            tip: "$0.00",
            surcharge: nil,
            card: "•••• 4242",
            cardBrand: "Visa",
            transactionId: "tx_abcdef1234567890",
            status: "Captured",
            statusReason: nil,
            approvalCode: "OK1234",
            processorResponseCode: "00",
            processorResponseMessage: "APPROVED",
            gatewayResponseMessage: "Approved"
        ),
        onDone: {}
    )
}

#Preview("Declined") {
    SaleResultSheet(
        result: .init(
            outcome: .declined,
            title: "Declined",
            total: "$46.00",
            subtotal: "$42.50",
            tax: "$3.50",
            tip: "$0.00",
            surcharge: nil,
            card: "•••• 0002",
            cardBrand: "Visa",
            transactionId: "tx_abcdef1234567890",
            status: "Declined",
            statusReason: "Insufficient funds",
            approvalCode: nil,
            processorResponseCode: "51",
            processorResponseMessage: "INSUFFICIENT FUNDS",
            gatewayResponseMessage: "Declined"
        ),
        onDone: {}
    )
}

#Preview("Processing") {
    SaleResultSheet(
        result: .init(
            outcome: .processing,
            title: "Processing…",
            total: "$46.00",
            subtotal: nil, tax: nil, tip: nil, surcharge: nil,
            card: nil, cardBrand: nil,
            transactionId: nil,
            status: "Waiting for gateway response",
            statusReason: nil
        ),
        onDone: {}
    )
}

#Preview("Cancelled") {
    SaleResultSheet(
        result: .init(
            outcome: .cancelled,
            title: "Cancelled",
            total: "$46.00",
            subtotal: nil, tax: nil, tip: nil, surcharge: nil,
            card: nil, cardBrand: nil,
            transactionId: nil,
            status: "Cancelled",
            statusReason: "Customer cancelled at the reader."
        ),
        onDone: {}
    )
}
