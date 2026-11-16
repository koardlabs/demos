import KoardSDK
import Observation
import SwiftUI

/// Pushed (not sheeted) details page for a single transaction. Scrollable,
/// status-first at the top, then card/amount, then breakdown, then
/// refunded/reversed lines (which call out the remaining refundable amount
/// if the txn is only partially refunded).
struct TransactionDetailsView: View {
    @State private var viewModel: TransactionDetailsViewModel
    @State private var pendingAction: PendingAction?

    enum PendingAction: String, Identifiable {
        case refund
        case reverse
        case capture
        case incrementalAuth
        case tipAdjust

        var id: String { rawValue }
    }

    init(viewModel: TransactionDetailsViewModel) {
        self.viewModel = viewModel
    }

    private var transaction: KoardTransaction { viewModel.transaction }
    private var currency: CurrencyCode {
        CurrencyCode(currencyCode: transaction.currency, displayName: nil)
    }

    private func money(_ cents: Int) -> String {
        MoneyUtils.centsToStringWithCurrency(cents, currency: currency)
    }

    /// "Surcharge (3%)" when the transaction carries a rate, "Surcharge"
    /// otherwise. Whole-number rates drop their trailing ".00".
    private var surchargeLabel: String {
        guard let rate = transaction.surchargeRate, rate > 0 else { return "Surcharge" }
        let formatted = (rate == rate.rounded())
            ? "\(Int(rate))%"
            : String(format: "%.2f%%", rate)
        return "Surcharge (\(formatted))"
    }

    /// Pulled from the transaction. Negative-clamped to 0 so a refunded
    /// transaction shows a non-negative remainder, never a sign trick.
    private var refundedCents: Int { max(0, transaction.refunded ?? 0) }
    private var reversedCents: Int { max(0, transaction.reversed ?? 0) }

    /// Anything not yet refunded. Used to default the refund amount and
    /// to gate whether the Refund button should appear at all.
    private var remainingRefundableCents: Int {
        max(0, transaction.totalAmount - refundedCents)
    }

    /// What "partially refunded" means in this view — some refund has
    /// happened, but the txn still has refundable balance left.
    private var isPartiallyRefunded: Bool {
        refundedCents > 0 && remainingRefundableCents > 0
    }

    var body: some View {
        ZStack {
            KoardBackgroundView()

            ScrollView {
                VStack(spacing: 12) {
                    combinedHeaderCard
                    breakdownCard
                    refundReversalCard
                    actionsCard
                    receiptDetailsLink
                    transactionIdCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingAction) { action in
            TransactionAmountActionSheet(
                action: action,
                transaction: transaction,
                refundCapCents: remainingRefundableCents,
                onDismiss: { pendingAction = nil },
                onPerform: { operationKind, amount in
                    pendingAction = nil
                    viewModel.performOperation(kind: operationKind, amount: amount)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $viewModel.operationPresentation) { _ in
            OperationStatusView(viewModel: viewModel)
        }
    }

    // MARK: - Cards

    /// Consolidated top card: status badge + status text + reason on the
    /// LEFT, total + card + date on the RIGHT. One card, two columns,
    /// no wasted vertical space. Uses `displayedTotalCents` so partial
    /// approvals show the authorized amount.
    private var combinedHeaderCard: some View {
        HStack(alignment: .top, spacing: 14) {
            // LEFT — status badge + text
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(transaction.status.statusColor.opacity(0.15))
                        .frame(width: 54, height: 54)
                    Image(systemName: statusIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(transaction.status.statusColor)
                }
                Text(transaction.status.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let reason = transaction.statusReason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Text(transaction.transactionTypeDisplayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.koardHairline.opacity(0.4)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // RIGHT — total + card + date
            VStack(alignment: .trailing, spacing: 6) {
                Text("Total")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(money(transaction.displayedTotalCents))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if !transaction.card.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "creditcard.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        if !transaction.cardBrand.isEmpty {
                            Text("\(transaction.cardBrand) · \(transaction.card)")
                        } else {
                            Text(transaction.card)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                }
                Text(dateString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.koardCardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.koardHairline, lineWidth: 0.5)
                )
        )
    }

    private var statusIcon: String {
        switch transaction.status.simple {
        case .approved: return "checkmark"
        case .failed: return "xmark"
        case .other: return "ellipsis"
        }
    }

    /// Navigation link to the dedicated full-receipt page. Replaces the
    /// inline receipt-details card that used to live on this page.
    private var receiptDetailsLink: some View {
        NavigationLink {
            ReceiptDetailsView(transaction: transaction)
        } label: {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.koardGreen)
                Text("View full receipt details")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.koardCardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.koardHairline, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var breakdownCard: some View {
        VStack(spacing: 10) {
            row("Subtotal", money(transaction.subtotal))
            if transaction.taxAmount > 0 {
                row("Tax", money(transaction.taxAmount))
            }
            if transaction.tipAmount > 0 {
                row("Tip", money(transaction.tipAmount))
            }
            if transaction.surchargeApplied, let s = transaction.surchargeAmount, s > 0 {
                row(surchargeLabel, money(s))
            }
            Divider().padding(.vertical, 2)
            row("Total", money(transaction.displayedTotalCents), bold: true)
            if transaction.isPartiallyApproved {
                row(
                    "Requested",
                    money(transaction.totalAmount),
                    valueColor: .secondary
                )
                row(
                    "Remaining",
                    money(transaction.partialApprovalRemainingCents),
                    bold: true,
                    valueColor: .orange
                )
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

    @ViewBuilder
    private var refundReversalCard: some View {
        if refundedCents > 0 || reversedCents > 0 {
            VStack(spacing: 10) {
                if refundedCents > 0 {
                    row("Refunded", money(refundedCents), valueColor: .red)
                }
                if reversedCents > 0 {
                    row("Reversed", money(reversedCents), valueColor: .orange)
                }
                if isPartiallyRefunded {
                    Divider().padding(.vertical, 2)
                    row(
                        "Remaining refundable",
                        money(remainingRefundableCents),
                        bold: true,
                        valueColor: .koardGreen
                    )
                    Text("Partially refunded — you can still issue a refund up to the remaining amount.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var transactionIdCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Transaction ID")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(transaction.transactionId)
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

    @ViewBuilder
    private var actionsCard: some View {
        // Status-driven action set — the single source of truth lives on
        // KoardTransaction.availableActions.
        let actions = transaction.availableActions

        if !actions.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                // Confirm — pending / surcharge-pending.
                if actions.contains(.confirm) {
                    actionButton(title: "Accept", tint: .koardGreen) {
                        viewModel.performOperation(kind: .confirm(accept: true), amount: 0)
                    }
                    actionButton(title: "Decline", tint: .red) {
                        viewModel.performOperation(kind: .confirm(accept: false), amount: 0)
                    }
                }
                // Partial approval — tap a different card for the remainder.
                if actions.contains(.completePartial) {
                    actionButton(
                        title: "Tap to Complete · \(money(transaction.partialApprovalRemainingCents))",
                        tint: .koardGreen
                    ) {
                        viewModel.performOperation(
                            kind: .completePartial,
                            amount: transaction.partialApprovalRemainingCents
                        )
                    }
                }
                if actions.contains(.refund) {
                    actionButton(
                        title: isPartiallyRefunded ? "Refund \(money(remainingRefundableCents))" : "Refund",
                        tint: .red
                    ) { pendingAction = .refund }
                }
                if actions.contains(.reverse) {
                    actionButton(title: "Reverse", tint: .orange) { pendingAction = .reverse }
                }
                if actions.contains(.capture) {
                    actionButton(title: "Capture", tint: .koardGreen) { pendingAction = .capture }
                }
                if actions.contains(.incrementalAuth) {
                    actionButton(title: "Incremental Auth", tint: .blue) { pendingAction = .incrementalAuth }
                }
                if actions.contains(.tipAdjust) {
                    actionButton(title: "Tip Adjust", tint: .purple) { pendingAction = .tipAdjust }
                }
            }
        }
    }

    private func actionButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: actionIcon(title))
                    .font(.title3)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(POSDesign.ink)
            }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(POSDesign.surface)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(POSDesign.line, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transaction.action.\(title)")
    }

    private func actionIcon(_ title: String) -> String {
        if title.hasPrefix("Refund") { return "arrow.uturn.backward" }
        if title.hasPrefix("Tap to Complete") { return "wave.3.right" }
        switch title {
        case "Capture": return "checkmark.rectangle"
        case "Incremental Auth": return "plus.circle"
        case "Tip Adjust": return "heart.circle"
        case "Reverse": return "arrow.counterclockwise"
        case "Accept": return "checkmark.circle"
        default: return "xmark.circle"
        }
    }

    // MARK: - Row builder + helpers

    private func row(_ label: String, _ value: String, bold: Bool = false, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(bold ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            Text(value)
                .font(bold ? .subheadline.weight(.bold) : .subheadline.weight(.medium))
                .foregroundStyle(valueColor)
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: transaction.createdAtDate)
    }
}

// MARK: - Amount-input sheet for refund/reverse/capture/incrementalAuth/tipAdjust

private struct TransactionAmountActionSheet: View {
    let action: TransactionDetailsView.PendingAction
    let transaction: KoardTransaction
    /// For refund actions, the max amount the user is allowed to refund —
    /// `totalAmount - already refunded`. The text field is clamped to this
    /// at submit time and the helper line surfaces it explicitly.
    let refundCapCents: Int
    let onDismiss: () -> Void
    let onPerform: (TransactionDetailsViewModel.OperationKind, Int) -> Void

    @State private var amountText: String
    @Environment(\.dismiss) private var dismiss

    init(
        action: TransactionDetailsView.PendingAction,
        transaction: KoardTransaction,
        refundCapCents: Int,
        onDismiss: @escaping () -> Void,
        onPerform: @escaping (TransactionDetailsViewModel.OperationKind, Int) -> Void
    ) {
        self.action = action
        self.transaction = transaction
        self.refundCapCents = refundCapCents
        self.onDismiss = onDismiss
        self.onPerform = onPerform

        let initialAmount: Int
        switch action {
        case .tipAdjust:
            initialAmount = transaction.tipAmount
        case .incrementalAuth:
            initialAmount = 0
        case .refund:
            // Default to the remaining refundable amount, not the original
            // total. Matches the user's intent for partial-refund-of-remainder.
            initialAmount = refundCapCents
        default:
            initialAmount = transaction.totalAmount
        }
        _amountText = State(initialValue: MoneyUtils.centsToString(initialAmount))
    }

    private var validatedAmountInCents: Int? { TransactionAmountInput.cents(from: amountText) }
    private var amountInCents: Int { validatedAmountInCents ?? 0 }

    private var clampedAmountForRefund: Int {
        min(amountInCents, refundCapCents)
    }

    private var amountDisplay: String {
        MoneyUtils.centsToStringWithCurrency(transaction.totalAmount)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.title3.weight(.bold))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Amount")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(MoneyUtils.symbol())
                            .foregroundStyle(.koardGreen)
                            .font(.system(size: 20, weight: .semibold))
                        TextField("0.00", text: $amountText)
                            .accessibilityIdentifier("transaction.amount")
                            .keyboardType(.decimalPad)
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.koardHairline, lineWidth: 1)
                    )
                }

                helperLine

                Spacer()

                actionButtons
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var helperLine: some View {
        switch action {
        case .refund:
            VStack(alignment: .leading, spacing: 2) {
                Text("Original total: \(amountDisplay)")
                Text("Max refundable: \(MoneyUtils.centsToStringWithCurrency(refundCapCents))")
                    .foregroundStyle(.koardGreen)
                if amountInCents > refundCapCents {
                    Text("Amount will be capped at the remaining refundable balance.")
                        .foregroundStyle(.red)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .tipAdjust:
            Text("Enter the new tip amount in dollars. The amount must be greater than zero.")
                .font(.footnote).foregroundStyle(.secondary)
        default:
            Text("Original total: \(amountDisplay)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch action {
        case .refund:
            VStack(spacing: 12) {
                Button {
                    perform(.refund(useTap: false), amount: clampedAmountForRefund)
                } label: {
                    Text("Refund")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(clampedAmountForRefund <= 0)

                Button {
                    perform(.refund(useTap: true), amount: clampedAmountForRefund)
                } label: {
                    Text("Refund With Tap")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(clampedAmountForRefund <= 0)
            }

        case .reverse:
            Button {
                perform(.reverse, amount: amountInCents)
            } label: {
                Text("Reverse")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(amountInCents <= 0)

        case .capture:
            Button {
                perform(.capture, amount: amountInCents)
            } label: {
                Text("Capture")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.koardGreen)
            .disabled(amountInCents <= 0)

        case .incrementalAuth:
            Button {
                perform(.incrementalAuth, amount: amountInCents)
            } label: {
                Text("Authorize Additional Amount")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(amountInCents <= 0)

        case .tipAdjust:
            Button {
                perform(.tipAdjust, amount: amountInCents)
            } label: {
                Text("Adjust Tip")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(validatedAmountInCents == nil || amountInCents <= 0)
        }
    }

    private func perform(_ kind: TransactionDetailsViewModel.OperationKind, amount: Int) {
        guard validatedAmountInCents != nil, amount > 0 else { return }
        dismiss()
        onDismiss()
        onPerform(kind, amount)
    }

    private var title: String {
        switch action {
        case .refund: return "Issue a Refund"
        case .reverse: return "Reverse Authorization"
        case .capture: return "Capture Authorization"
        case .incrementalAuth: return "Incremental Authorization"
        case .tipAdjust: return "Adjust Tip"
        }
    }
}

// MARK: - Operation status overlay (unchanged from previous version)

private struct OperationStatusView: View {
    @Bindable var viewModel: TransactionDetailsViewModel

    var body: some View {
        ZStack {
            KoardBackgroundView()
                .ignoresSafeArea()

            if let presentation = viewModel.operationPresentation {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            viewModel.dismissOperation()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                    }

                    Spacer()

                    content(for: presentation)
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.horizontal, 24)

                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func content(for presentation: TransactionDetailsViewModel.OperationPresentation) -> some View {
        let amount = MoneyUtils.centsToStringWithCurrency(presentation.amount, currency: presentation.currency)

        switch presentation.phase {
        case .processing:
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.koardGreen)
                    .scaleEffect(1.4)

                Text(presentation.kind.progressMessage)
                    .font(.title3.weight(.semibold))

                Text("Amount: \(amount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

        case .success(let updatedTransaction):
            let statusText = updatedTransaction.status.displayName
            let transactionId = updatedTransaction.transactionId
            let processorMessage = updatedTransaction.statusReason ?? updatedTransaction.processorResponseMessage

            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.koardGreen)

                Text("\(presentation.kind.title) Completed")
                    .font(.title2.weight(.bold))

                VStack(spacing: 6) {
                    Text("Status: \(statusText)")
                        .font(.body)
                    Text("Amount: \(amount)")
                        .font(.body)
                    Text("Transaction ID: \(transactionId)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let processorMessage, !processorMessage.isEmpty {
                        Text(processorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Button {
                    viewModel.dismissOperation()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.koardGreen)
            }

        case .failure(let errorMessage):
            VStack(spacing: 16) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.red)

                Text("Unable to Complete")
                    .font(.title2.weight(.bold))

                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    viewModel.dismissOperation()
                } label: {
                    Text("Dismiss")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

        case .cancelled:
            VStack(spacing: 16) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)

                Text("\(presentation.kind.title) Cancelled")
                    .font(.title2.weight(.bold))

                Text("Cancelled at the reader.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    viewModel.dismissOperation()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.koardGreen)
            }
        }
    }
}

#Preview {
    NavigationStack {
        TransactionDetailsView(
            viewModel: .init(
                koardMerchantService: .mockMerchantService,
                transaction: .mockApprovedTransaction,
                delegate: .init(onTransactionUpdate: {})
            )
        )
    }
}
