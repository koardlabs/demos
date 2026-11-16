import Foundation
import KoardSDK

@MainActor
@Observable
public final class TransactionDetailsViewModel: Identifiable {
    public enum OperationKind: Hashable {
        case refund(useTap: Bool)
        case reverse
        case capture
        case incrementalAuth
        case tipAdjust
        case confirm(accept: Bool)
        case completePartial

        var title: String {
            switch self {
            case .refund(let useTap):
                return useTap ? "Tap Refund" : "Refund"
            case .reverse:
                return "Reverse"
            case .capture:
                return "Capture"
            case .incrementalAuth:
                return "Incremental Auth"
            case .tipAdjust:
                return "Tip Adjust"
            case .confirm(let accept):
                return accept ? "Confirm" : "Decline"
            case .completePartial:
                return "Complete Payment"
            }
        }

        var progressMessage: String {
            switch self {
            case .refund(let useTap):
                return useTap ? "Processing tap refund…" : "Processing refund…"
            case .reverse:
                return "Reversing transaction…"
            case .capture:
                return "Capturing transaction…"
            case .incrementalAuth:
                return "Authorizing additional amount…"
            case .tipAdjust:
                return "Adjusting tip…"
            case .confirm(let accept):
                return accept ? "Confirming…" : "Declining…"
            case .completePartial:
                return "Charging remaining amount…"
            }
        }
    }

    public struct OperationPresentation: Identifiable {
        public enum Phase {
            case processing
            case success(KoardTransaction)
            case failure(String)
            /// The customer cancelled at the Tap to Pay sheet — a benign
            /// outcome, rendered distinctly from a failure.
            case cancelled
        }

        public let id: UUID
        public let kind: OperationKind
        public let amount: Int
        public let currency: CurrencyCode
        public var phase: Phase

        init(
            id: UUID = UUID(),
            kind: OperationKind,
            amount: Int,
            currency: CurrencyCode,
            phase: Phase
        ) {
            self.id = id
            self.kind = kind
            self.amount = amount
            self.currency = currency
            self.phase = phase
        }
    }

    public private(set) var transaction: KoardTransaction
    public var operationPresentation: OperationPresentation?

    @ObservationIgnored public let id: UUID = UUID()
    @ObservationIgnored public var delegate: Delegate
    @ObservationIgnored private let koardMerchantService: KoardMerchantServiceable

    public struct Delegate {
        public var onTransactionUpdate: () -> Void

        public init(
            onTransactionUpdate: @escaping () -> Void
        ) {
            self.onTransactionUpdate = onTransactionUpdate
        }
    }

    init(
        koardMerchantService: KoardMerchantServiceable,
        transaction: KoardTransaction,
        delegate: Delegate
    ) {
        self.koardMerchantService = koardMerchantService
        self.transaction = transaction
        self.delegate = delegate
    }

    public func performOperation(kind: OperationKind, amount: Int) {
        let currency = CurrencyCode(currencyCode: transaction.currency, displayName: nil)
        let identifier = UUID()
        operationPresentation = OperationPresentation(
            id: identifier,
            kind: kind,
            amount: amount,
            currency: currency,
            phase: .processing
        )

        Task {
            do {
                let updatedTransaction = try await executeOperation(kind: kind, amount: amount)
                await MainActor.run {
                    operationPresentation = OperationPresentation(
                        id: identifier,
                        kind: kind,
                        amount: amount,
                        currency: currency,
                        phase: .success(updatedTransaction)
                    )

                    transaction = updatedTransaction
                    delegate.onTransactionUpdate()
                }
            } catch {
                await MainActor.run {
                    let phase: OperationPresentation.Phase
                    if let sdkError = error as? KoardMerchantSDKError, sdkError.isReaderCancellation {
                        // Customer cancelled at the reader — not a failure. Uses the
                        // same fuzzy detection as PinPadViewModel so tap refunds /
                        // partial completions treat a reader cancel consistently.
                        phase = .cancelled
                    } else if let describable = error as? KoardDescribableError {
                        // Use the SDK's human-readable message rather than the
                        // generic NSError "couldn't be completed" description.
                        phase = .failure(describable.errorDescription)
                    } else {
                        phase = .failure(error.localizedDescription)
                    }
                    operationPresentation = OperationPresentation(
                        id: identifier,
                        kind: kind,
                        amount: amount,
                        currency: currency,
                        phase: phase
                    )
                }
            }
        }
    }

    public func dismissOperation() {
        operationPresentation = nil
    }

    /// Runs the SDK operation for `kind` and returns the resulting updated
    /// transaction. The reader-driven / server ops return a `TransactionResponse`
    /// whose `.transaction` we unwrap (falling back to the current transaction
    /// if the wrapper didn't include one); `.confirm` returns a `KoardTransaction`
    /// directly.
    private func executeOperation(kind: OperationKind, amount: Int) async throws -> KoardTransaction {
        switch kind {
        case .refund(let useTap):
            let response = try await koardMerchantService.refund(
                transactionID: transaction.transactionId,
                amount: amount,
                eventId: UUID().uuidString,
                withTap: useTap
            )
            return response.transaction ?? transaction

        case .reverse:
            let response = try await koardMerchantService.reverse(
                transactionId: transaction.transactionId,
                amount: amount
            )
            return response.transaction ?? transaction

        case .capture:
            let response = try await koardMerchantService.captureTransaction(
                transactionId: transaction.transactionId,
                amount: amount
            )
            return response.transaction ?? transaction

        case .incrementalAuth:
            let response = try await koardMerchantService.incrementalAuth(
                transactionId: transaction.transactionId,
                amount: amount
            )
            return response.transaction ?? transaction

        case .tipAdjust:
            // Tip adjust: amount is the new total tip amount in cents
            let tipType: PaymentBreakdown.TipType = .fixed
            let response = try await koardMerchantService.tipAdjust(
                transactionId: transaction.transactionId,
                amount: amount,
                tipType: tipType
            )
            return response.transaction ?? transaction

        case .confirm(let accept):
            // Accept / decline a pending or surcharge-pending transaction.
            return try await koardMerchantService.transactionConfirmed(
                transactionId: transaction.transactionId,
                confirm: accept,
                amount: nil,
                breakdown: nil,
                eventId: nil
            )

        case .completePartial:
            // Tap a different card for the remaining balance, repeating the
            // parent's flow (preauth for an authorized parent, else sale).
            let response = try await koardMerchantService.completePartialApproval(
                originalTransactionId: transaction.transactionId,
                amount: amount,
                asPreauth: transaction.status == .authorized
            )
            return response.transaction ?? transaction
        }
    }
}

extension TransactionDetailsViewModel: Hashable {
    public nonisolated static func == (lhs: TransactionDetailsViewModel, rhs: TransactionDetailsViewModel) -> Bool {
        lhs.id == rhs.id
    }

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
