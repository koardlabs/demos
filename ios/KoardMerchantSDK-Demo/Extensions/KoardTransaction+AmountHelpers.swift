import Foundation
import KoardSDK

/// Amount-display and partial-approval helpers for `KoardTransaction`.
///
/// The header amount the user sees on receipts / history rows / details
/// pages should be the amount the **issuer actually approved**
/// (`gatewayTransactionResponse.authorizedAmount`), not the amount we
/// asked for (`totalAmount`). They're the same for fully-approved
/// transactions, but they diverge on partial approvals.
///
/// **Partial approval signal.** The gateway flags a partial approval via
/// `status_reason == "partial_approval"` on the transaction body — NOT
/// via the top-level `status` enum (which stays at `.approved` /
/// `.captured` / `.authorized` for these). So our `isPartiallyApproved`
/// check is a raw string match against `statusReason`, not anything on
/// the Status enum, and not a fallback comparison of authorizedAmount vs
/// totalAmount (which can match-or-not depending on gateway quirks).
extension KoardTransaction {
    /// Best authoritative amount to surface to the cashier / customer.
    /// Falls back to `totalAmount` when the gateway didn't return an
    /// explicit `authorizedAmount`.
    public var displayedTotalCents: Int {
        gatewayTransactionResponse?.authorizedAmount ?? totalAmount
    }

    /// `true` iff the gateway flagged this transaction as a partial
    /// approval via `status_reason`. We deliberately don't infer from
    /// `authorizedAmount < totalAmount` because gateways aren't
    /// consistent about whether they populate `authorizedAmount` at all
    /// on full approvals.
    ///
    /// Compares against `StatusReason.partialApproval.rawValue` from the
    /// SDK so when the SDK enum changes the value, the demo follows
    /// automatically.
    public var isPartiallyApproved: Bool {
        // Primary signal: the gateway's explicit partial-approval status_reason.
        if let reason = statusReason?.lowercased(), reason == StatusReason.partialApproval.rawValue {
            return true
        }
        // Fallback: the issuer authorized a real amount that's below what we
        // asked for. Guard on `> 0` so a full approval that leaves
        // authorizedAmount nil/0 never false-positives as partial.
        if let authorized = gatewayTransactionResponse?.authorizedAmount, authorized > 0, authorized < totalAmount {
            return true
        }
        return false
    }

    /// Amount still owed when this transaction was a partial approval.
    /// Returns 0 when the transaction was fully approved or wasn't
    /// approved at all. Derived from `totalAmount - authorizedAmount`
    /// once `isPartiallyApproved` is true.
    public var partialApprovalRemainingCents: Int {
        guard isPartiallyApproved else { return 0 }
        let authorized = gatewayTransactionResponse?.authorizedAmount ?? 0
        return max(0, totalAmount - authorized)
    }
}
