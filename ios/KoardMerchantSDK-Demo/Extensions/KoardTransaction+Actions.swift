import Foundation
import KoardSDK

/// Post-sale actions the transaction detail view can offer, gated by the
/// transaction's status (plus the partial-approval signal). Single source of
/// truth the detail view renders buttons from.
///
///  - Authorized          → capture, incremental, reverse, tip-adjust, refund
///  - Captured            → incremental, reverse, tip-adjust, refund        [no re-capture]
///  - Settled             → refund
///  - Pending / SurchargePending → confirm (accept / decline)
///  - Partially approved  → complete-partial (re-tap a different card), additive to the above
///
/// (Refund itself offers both tap and no-tap from its amount sheet, so it's a
/// single action here.)
enum TransactionAction {
    case confirm
    case capture
    case incrementalAuth
    case reverse
    case tipAdjust
    case refund
    case completePartial
}

extension KoardTransaction {
    /// Amount still refundable — original total minus whatever's already been
    /// refunded, clamped at 0.
    var remainingRefundableCents: Int {
        max(0, totalAmount - (refunded ?? 0))
    }

    /// The set of actions valid for this transaction's current state.
    var availableActions: Set<TransactionAction> {
        var actions: Set<TransactionAction> = []

        switch status {
        case .pending, .surchargePending:
            actions.insert(.confirm)

        case .authorized:
            actions.insert(.capture)
            actions.insert(.incrementalAuth)
            actions.insert(.reverse)
            actions.insert(.tipAdjust)
            if remainingRefundableCents > 0 { actions.insert(.refund) }

        case .captured:
            actions.insert(.incrementalAuth)
            actions.insert(.reverse)
            actions.insert(.tipAdjust)
            if remainingRefundableCents > 0 { actions.insert(.refund) }

        case .settled:
            if remainingRefundableCents > 0 { actions.insert(.refund) }

        default:
            break
        }

        if isPartiallyApproved, partialApprovalRemainingCents > 0 {
            actions.insert(.completePartial)
        }

        return actions
    }
}
