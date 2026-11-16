import KoardSDK
import SwiftUI

/// Full-fidelity receipt dump. Reached by tapping "View full receipt
/// details" on the consolidated `TransactionDetailsView`. Surfaces every
/// processor- and gateway-side field the SDK returned plus the raw
/// `additionalDetails` map and any parsed EMV tags — useful for
/// debugging or for showing a customer "everything we know about this
/// transaction" without crowding the main details page.
struct ReceiptDetailsView: View {
    let transaction: KoardTransaction

    private var currency: CurrencyCode {
        CurrencyCode(currencyCode: transaction.currency, displayName: nil)
    }

    private func money(_ cents: Int) -> String {
        MoneyUtils.centsToStringWithCurrency(cents, currency: currency)
    }

    var body: some View {
        ZStack {
            KoardBackgroundView()

            ScrollView {
                VStack(spacing: 16) {
                    coreSection
                    gatewaySection
                    additionalDetailsSection
                    emvTagsSection
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Receipt details")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Core / transaction fields

    private var coreSection: some View {
        card(title: "Transaction") {
            row("Transaction ID", transaction.transactionId, monospaced: true)
            row("Event ID", transaction.eventId, monospaced: true)
            row("Type", transaction.transactionTypeDisplayName)
            row("Status", transaction.status.displayName)
            if let reason = transaction.statusReason, !reason.isEmpty {
                row("Status reason", reason)
            }
            row("Subtotal", money(transaction.subtotal))
            if transaction.taxAmount > 0 { row("Tax", money(transaction.taxAmount)) }
            if transaction.tipAmount > 0 { row("Tip", money(transaction.tipAmount)) }
            if transaction.surchargeApplied,
               let surchargeAmount = transaction.surchargeAmount,
               surchargeAmount > 0 {
                row("Surcharge", money(surchargeAmount))
                if let rate = transaction.surchargeRate, rate > 0 {
                    row("Surcharge rate", String(format: "%.2f%%", rate))
                }
            }
            row("Total amount", money(transaction.totalAmount))
            if let authorized = transaction.gatewayTransactionResponse?.authorizedAmount,
               authorized != transaction.totalAmount {
                row("Authorized amount", money(authorized))
            }
            if let refunded = transaction.refunded, refunded > 0 {
                row("Refunded", money(refunded))
            }
            if let reversed = transaction.reversed, reversed > 0 {
                row("Reversed", money(reversed))
            }
            row("Card", "\(transaction.cardBrand) \(transaction.card)".trimmingCharacters(in: .whitespaces))
            row("TID", transaction.tid, monospaced: true)
            if let batchId = transaction.batchId, !batchId.isEmpty {
                row("Batch ID", batchId, monospaced: true)
            }
            if let locationId = transaction.locationId, !locationId.isEmpty {
                row("Location ID", locationId, monospaced: true)
            }
            if let code = transaction.processorResponseCode, !code.isEmpty {
                row("Processor response code", code, monospaced: true)
            }
            if let msg = transaction.processorResponseMessage, !msg.isEmpty {
                row("Processor response message", msg)
            }
            row("Created", DateFormatter.mediumDateFormatter.string(from: transaction.createdAtDate))
        }
    }

    // MARK: - Gateway response

    @ViewBuilder
    private var gatewaySection: some View {
        if let gateway = transaction.gatewayTransactionResponse {
            card(title: "Gateway response") {
                if let type = gateway.type, !type.isEmpty {
                    row("Type", type)
                }
                if let status = gateway.status, !status.isEmpty {
                    row("Status", status)
                }
                if let curr = gateway.currency, !curr.isEmpty {
                    row("Currency", curr)
                }
                if let code = gateway.approvalCode, !code.isEmpty {
                    row("Approval code", code, monospaced: true)
                }
                if let code = gateway.responseCode, !code.isEmpty {
                    row("Response code", code, monospaced: true)
                }
                if let msg = gateway.responseMessage, !msg.isEmpty {
                    row("Response message", msg)
                }
                if let authorized = gateway.authorizedAmount {
                    row("Authorized amount", money(authorized))
                }
                if let code = gateway.processorResponseCode, !code.isEmpty {
                    row("Processor response code", code, monospaced: true)
                }
            }
        }
    }

    // MARK: - additionalDetails dump

    @ViewBuilder
    private var additionalDetailsSection: some View {
        if let details = transaction.additionalDetails, !details.isEmpty {
            card(title: "Additional details") {
                ForEach(details.keys.sorted(), id: \.self) { key in
                    let value = details[key]
                    row(key, valueString(for: value), monospaced: true)
                }
            }
        }
    }

    private func valueString(for value: Any?) -> String {
        guard let value else { return "nil" }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let arr = value as? [Any] { return arr.map { valueString(for: $0) }.joined(separator: ", ") }
        if let dict = value as? [String: Any] {
            return dict.map { "\($0.key)=\(valueString(for: $0.value))" }.joined(separator: ", ")
        }
        return String(describing: value)
    }

    // MARK: - EMV tags

    @ViewBuilder
    private var emvTagsSection: some View {
        if let tags = transaction.emvTags(), !tags.isEmpty {
            card(title: "EMV tags") {
                ForEach(tags.keys.sorted(), id: \.self) { tag in
                    if let entry = tags[tag] {
                        let name = entry["name"] ?? tag
                        let value = entry["value"] ?? ""
                        row("\(tag) · \(name)", value, monospaced: true)
                    }
                }
            }
        }
    }

    // MARK: - Card / row helpers

    private func card<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func row(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced ? .system(.footnote, design: .monospaced).weight(.medium)
                                 : .footnote.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    NavigationStack {
        ReceiptDetailsView(transaction: .mockApprovedTransaction)
    }
}
