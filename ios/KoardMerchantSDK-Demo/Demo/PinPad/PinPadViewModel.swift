import Foundation
import KoardSDK
import SwiftUI

/// The driver for the pin-pad checkout. Coordinates the three sheets the
/// pin pad can present:
///
/// 1. **Review sheet** — opens when the user hits Charge. Shows subtotal,
///    tax (from settings), tip selector, total, Confirm. One sheet for
///    Retail and Restaurant/Bar; only the header copy differs.
/// 2. **Preparing modal** — opens automatically if the user confirms a
///    charge while the reader isn't ready. Tracks `updateProgress` events
///    and auto-fires the sale as soon as the reader hits ready.
/// 3. **Result sheet** — shows after the sale completes. Approved /
///    declined / error with the full receipt-shaped summary.
///
/// Surcharge confirmation, returned by the SDK when a charge needs an
/// extra customer approval, lives in its own fullScreenCover flow.
@MainActor
@Observable
public final class PinPadViewModel: Identifiable {
    /// Every transaction-flow popup shares this enum and — critically —
    /// shares the SAME identifier. SwiftUI uses the `Identifiable.id` to
    /// decide whether to dismiss/re-present a `.sheet(item:)`, so by
    /// returning the same id across all cases we keep ONE bottom sheet
    /// mounted that just swaps its content as the flow progresses:
    ///
    ///     review → preparingReader → result(.processing) → result(.approved/declined/…)
    ///     review → result(.processing) → result(.partiallyApproved) → result(.processing) → …
    ///     review → result(.processing) → surcharge → result(.processing) → result(.approved)
    ///     review → result(.processing) → tipEntry → result(.processing) → result(.approved)
    ///
    /// No dismiss/re-present flicker, no second popover ever stacking on
    /// top of another. One sheet for the whole life of a transaction.
    enum Sheet: Identifiable, Equatable {
        case review(ChargeReviewContext)
        case result(SaleResultSheet.ResultData)
        /// Restaurant flow only: customer-facing tip entry that's shown
        /// AFTER the sale is approved. Confirm here triggers `tipAdjust()`
        /// then transitions to the settled result.
        case tipEntry(TipEntryContext)
        /// Customer-facing surcharge confirmation. Reached when the
        /// gateway returns `.surchargePending` and the customer needs to
        /// accept/decline the added fee.
        case surcharge(SurchargePrompt)
        /// Reader was not yet ready when the user confirmed a charge.
        /// Sits here with a progress bar until ReaderStateManager hits
        /// `.ready`, at which point we auto-transition to .result(.processing).
        case preparingReader

        /// CONSTANT id — every txn-flow case returns "txn" so SwiftUI
        /// treats the whole sequence as one continuously-mounted sheet.
        var id: String { "txn" }

        /// Whether the user is allowed to swipe this case down to dismiss.
        /// Only the pre-charge review sheet (subtotal/tax/tip with the
        /// Auth/Sale + Cancel buttons) is swipe-dismissable — swiping it is
        /// equivalent to tapping Cancel, since nothing has been charged yet.
        /// Every other case is mid-transaction (processing, surcharge,
        /// result, post-sale tip, reader prep) and must be committed via its
        /// own explicit button, so it stays locked.
        var allowsInteractiveDismiss: Bool {
            switch self {
            case .review: return true
            case .result, .tipEntry, .surcharge, .preparingReader: return false
            }
        }
    }

    struct ChargeReviewContext: Equatable {
        let style: ChargeReviewSheet.Style
        let subtotalCents: Int
        let taxCents: Int
        let taxRatePercent: Double
        /// Fixed surcharge rate to fold into the review total, or 0 when the
        /// active surcharge mode isn't a fixed-rate override.
        let surchargeRatePercent: Double
        /// True if this review screen should let the user pick a tip
        /// up front (retail), false if the tip is going to be collected
        /// after the sale via `tipAdjust` (restaurant).
        let collectsTipUpFront: Bool

        static func == (lhs: ChargeReviewContext, rhs: ChargeReviewContext) -> Bool {
            lhs.subtotalCents == rhs.subtotalCents &&
                lhs.taxCents == rhs.taxCents &&
                lhs.taxRatePercent == rhs.taxRatePercent &&
                lhs.surchargeRatePercent == rhs.surchargeRatePercent &&
                lhs.collectsTipUpFront == rhs.collectsTipUpFront &&
                lhs.styleKey == rhs.styleKey
        }

        private var styleKey: String {
            switch style {
            case .retail: return "retail"
            case .restaurant: return "restaurant"
            }
        }
    }

    /// Snapshot of the just-approved sale, used to drive the customer-
    /// facing tip entry sheet shown after sale in restaurant mode.
    struct TipEntryContext: Equatable {
        let transactionId: String
        let currency: String
        let subtotalCents: Int
        let taxCents: Int
        /// What was actually charged (subtotal + tax + any surcharge). The
        /// tip is added on top of this and submitted via tipAdjust.
        let chargedTotalCents: Int
    }

    /// Whether the in-flight charge should run as a Sale (auth + capture
    /// in one shot, money moves immediately) or a Preauthorization (auth
    /// only, separate capture later). Both are surfaced as side-by-side
    /// buttons on the review sheet — the cashier picks per transaction.
    public enum FlowType: Equatable {
        case sale
        case preauth

        public var verb: String {
            switch self {
            case .sale: return "Sale"
            case .preauth: return "Auth"
            }
        }
    }

    /// Snapshot captured at Charge-time so the preparing modal can fire
    /// the same charge after the reader becomes ready, without needing to
    /// reach back into the keypad state.
    public struct PendingSale: Equatable {
        public let subtotalCents: Int
        public let taxCents: Int
        public let tipCents: Int
        /// Override surcharge folded into the charged amount (0 unless the
        /// active mode is a fixed-rate override). For `.sale` the service
        /// recomputes the same figure from the breakdown; for `.preauth`
        /// this is what makes the surcharge actually reach the charged
        /// amount (preauth passes `totalCents` straight through).
        public let surchargeCents: Int
        public let flow: FlowType
        public var totalCents: Int { subtotalCents + taxCents + tipCents + surchargeCents }
    }

    public struct SurchargePrompt: Identifiable, Equatable {
        public let id = UUID()
        public let transactionId: String
        public let disclosure: String
        public let baseAmountCents: Int
        public let surchargeAmountCents: Int
        public let currency: String

        public var totalCents: Int { baseAmountCents + surchargeAmountCents }
    }

    public var amount = PinPadAmount()
    /// Single source of truth for ANY transaction-flow popup. Setting
    /// this presents the unified bottom sheet; setting it to nil
    /// dismisses. Don't add new fullScreenCovers / popovers / sheets to
    /// PinPadView — extend `Sheet` instead so the one-sheet contract
    /// continues to hold.
    var sheet: Sheet?
    public private(set) var isProcessing: Bool = false
    public private(set) var selectedLocation: Location?
    public private(set) var availableLocations: [Location] = []
    public private(set) var isLoadingLocations = false
    private(set) var pendingSale: PendingSale?
    /// Set while we're routed through the post-sale tip entry sheet
    /// (restaurant flow). Holds the approved sale so `tipAdjust` can
    /// reference it and `recordSuccess` can show the final receipt.
    private var transactionAwaitingTip: KoardTransaction?
    /// Leftover amount when the issuer only partially authorized. Drives
    /// the "Tap for remaining $X" button on the result sheet.
    private(set) var partialApprovalRemainder: Int?
    /// Which flow (sale vs preauth) the original partial charge ran as.
    /// We repeat that flow when the customer taps another card so the
    /// gateway-side audit trail stays consistent.
    private var partialApprovalFlow: FlowType?
    /// Tracks the flow of the most recent charge dispatch so partial-
    /// approval continuations know which API to fire.
    private var lastChargeFlow: FlowType = .sale

    @ObservationIgnored public let id = UUID()
    @ObservationIgnored private let koardMerchantService: KoardMerchantServiceable
    /// NOT @ObservationIgnored — the view body reads `readerState.state`
    /// and `readerState.progress` and we want those changes to redraw.
    public let readerState: ReaderStateManager
    @ObservationIgnored private var appSettings: AppSettings { .shared }

    public init(
        koardMerchantService: KoardMerchantServiceable,
        readerState: ReaderStateManager
    ) {
        self.koardMerchantService = koardMerchantService
        self.readerState = readerState
        self.selectedLocation = koardMerchantService.activeLocation
    }

    // MARK: - Keypad

    public func keyTapped(_ key: PinPadKey) {
        switch key {
        case let .digit(d):
            amount.append(digit: d)
        case .doubleZero:
            amount.append(digit: 0)
            amount.append(digit: 0)
        case .backspace:
            amount.backspace()
        }
    }

    public func clearAmount() {
        amount.clear()
    }

    /// Accept the ticket subtotal without changing tax, tip, or surcharge rules.
    public func setSubtotalCents(_ cents: Int) {
        guard !isProcessing, sheet == nil else { return }
        amount = PinPadAmount(cents: cents)
    }

    // MARK: - Charge → Review sheet

    /// The Charge button on the pin pad. Computes the tax and opens the
    /// review sheet. Both Retail and Restaurant/Bar route through this —
    /// only the sheet style differs.
    public func chargeButtonTapped(mode: AppSettings.CheckoutMode) {
        guard amount.cents > 0 else { return }
        let style: ChargeReviewSheet.Style = (mode == .restaurantBar) ? .restaurant : .retail
        let taxCents = appSettings.taxCents(forSubtotalCents: amount.cents)
        // RESTAURANT MODE: tip is collected AFTER the sale via tipAdjust,
        // not on the review screen. The cashier confirms subtotal+tax,
        // hands the device to the customer, customer taps for the bill,
        // customer then enters a tip on the device.
        //
        // RETAIL MODE: tip on the review up-front as before.
        let collectsTipUpFront = (mode != .restaurantBar)
        sheet = .review(.init(
            style: style,
            subtotalCents: amount.cents,
            taxCents: taxCents,
            taxRatePercent: appSettings.taxEnabled ? appSettings.taxRatePercent : 0,
            surchargeRatePercent: appSettings.surchargeMode == .overridePercent
                ? appSettings.surchargeOverrideRatePercent : 0,
            collectsTipUpFront: collectsTipUpFront
        ))
    }

    public func reviewConfirmed(tipCents: Int, flow: FlowType) {
        guard case let .review(context) = sheet else { return }
        // If the review screen wasn't collecting a tip (restaurant flow),
        // force tipCents to 0 here so we send `sale()`/`preauth()` for
        // just subtotal+tax — the tip will be added later via tipAdjust.
        let effectiveTip = context.collectsTipUpFront ? max(0, tipCents) : 0
        // Same base the service uses for the override surcharge (subtotal +
        // tax + tip) so the charged total matches what the review showed.
        let surchargeCents = appSettings.overrideSurchargeCents(
            forBaseCents: context.subtotalCents + context.taxCents + effectiveTip
        )
        let pending = PendingSale(
            subtotalCents: context.subtotalCents,
            taxCents: context.taxCents,
            tipCents: effectiveTip,
            surchargeCents: surchargeCents,
            flow: flow
        )
        pendingSale = pending
        sheet = nil
        Task { await runPendingSale() }
    }

    public func reviewCancelled() {
        sheet = nil
    }

    // MARK: - Preparing modal

    /// Called by `ReaderPreparingModal` (now rendered inside the unified
    /// sheet) once the reader hits ready. We DON'T clear the sheet here
    /// — `executePendingSale` immediately swaps it to .result(processing)
    /// so the user perceives a continuous bottom sheet that just morphs.
    public func preparingModalReady() {
        guard pendingSale != nil else { return }
        Task { await executePendingSale() }
    }

    /// User explicitly cancelled while the preparing modal was up.
    public func preparingModalDismissed() {
        sheet = nil
        pendingSale = nil
    }

    // MARK: - Sale execution

    /// Routes the pending sale either directly (reader ready) or through
    /// the preparing modal (reader not ready).
    private func runPendingSale() async {
        guard pendingSale != nil else { return }

        switch readerState.state {
        case .ready:
            await executePendingSale()
        case .preparing, .idle, .failed:
            // Pop the preparing case inside the unified sheet — it'll
            // morph to .result(.processing) once ready.
            readerState.ensureReady(force: readerState.state.isFailed)
            sheet = .preparingReader
        case .unsupported:
            sheet = .result(.init(
                outcome: .error,
                title: "Unable to charge",
                total: MoneyUtils.centsToStringWithCurrency(pendingSale?.totalCents ?? 0),
                subtotal: nil, tax: nil, tip: nil, surcharge: nil,
                card: nil, cardBrand: nil, transactionId: nil,
                status: "Tap to Pay unsupported",
                statusReason: "This device cannot accept Tap to Pay sales."
            ))
            pendingSale = nil
        }
    }

    private func executePendingSale() async {
        guard let pending = pendingSale else { return }
        lastChargeFlow = pending.flow
        isProcessing = true
        // Pop the result sheet IMMEDIATELY in its processing state so the
        // cashier sees feedback the second the network call starts. Will
        // be swapped in-place to the settled outcome by recordSuccess /
        // recordDeclined / recordCancelled / recordError when we get the
        // response back. The sheet is marked non-dismissable so the user
        // can't accidentally swipe it away mid-charge.
        sheet = .result(processingResultData(forTotalCents: pending.totalCents))
        defer { isProcessing = false }

        do {
            let transaction = try await runChargeAgainstSDK(pending: pending)
            try await handleTransactionStatus(transaction, fallback: pending)
        } catch let sdkError as KoardMerchantSDKError {
            // If this is a TTP-failure because the reader was never actually
            // ready (e.g. the cached state lied or a race threaded through),
            // re-show the preparing modal instead of a generic "Sale failed".
            // We KEEP `pendingSale` set so when prepare completes the modal
            // re-fires the same sale.
            if isReaderNotReady(sdkError) {
                // Reader wasn't actually ready — morph the sheet from
                // .result(.processing) to .preparingReader. When prep
                // completes, executePendingSale fires again and the
                // sheet morphs back to .result(.processing) for the
                // real run. Same sheet throughout.
                readerState.ensureReady(force: true)
                sheet = .preparingReader
                isProcessing = false
                return
            }
            // Cancellation by the customer at the Apple TTP sheet is a
            // legitimate non-error outcome — surface it as "Cancelled",
            // not "Sale failed".
            if isCancellation(sdkError) {
                recordCancelled(pending: pending)
            } else {
                // Title names the flow; recordError() derives the specific
                // detail line (e.g. "Server error (HTTP 500)") from the error.
                recordError("Sale failed", error: sdkError, pending: pending)
            }
        } catch {
            // recordError() already unwraps KoardDescribableError internally, so
            // a single generic catch covers both describable and opaque errors.
            recordError("Sale failed", error: error, pending: pending)
        }
        pendingSale = nil
    }

    private func handleTransactionStatus(_ transaction: KoardTransaction, fallback pending: PendingSale) async throws {
        switch transaction.status {
        // Success: gateway captured / authorized / settled the transaction,
        // or the surcharge was auto-applied (merchant has surcharge configured
        // to not require explicit customer confirmation).
        case .captured, .authorized, .approved, .surchargeApplied, .settled:
            recordSuccess(transaction: transaction, fallback: pending)

        // Surcharge requires customer confirmation — morph the sheet
        // from .result(.processing) to .surcharge inside the unified
        // sheet. After Accept, the SDK returns an updated transaction
        // in a settled status which goes back through this switch.
        case .surchargePending:
            let surchargeAmount = transaction.surchargeAmount ?? 0
            let baseAmount = max(0, transaction.totalAmount - surchargeAmount)
            let disclosure = transaction.surchargeDisclosure ?? defaultSurchargeDisclosure(rate: transaction.surchargeRate)
            sheet = .surcharge(SurchargePrompt(
                transactionId: transaction.transactionId,
                disclosure: disclosure,
                baseAmountCents: baseAmount,
                surchargeAmountCents: surchargeAmount,
                currency: transaction.currency
            ))

        // Gateway said pending — accepted but not finalized. Show the user
        // a "Pending" result with the transaction ID so they can check
        // History → Detail later for the eventual settled state.
        case .pending:
            recordPending(transaction: transaction)

        case .declined:
            recordDeclined(transaction: transaction, fallback: pending)

        // Gateway-side cancellation (distinct from Apple-TTP-sheet
        // cancellation, which we catch in the error path above).
        case .canceled, .cancelled:
            recordCancelled(pending: pending)

        // Hard failures — bad input, comms timeout, "pickup card" alert
        // from issuer, unknown gateway state.
        case .error, .timedOut, .pickupCard, .reversed, .refunded, .unknown:
            recordError("Transaction \(transaction.status.displayName)",
                        error: PaymentError.invalidTransaction,
                        pending: pending,
                        transaction: transaction)

        @unknown default:
            recordError("Transaction \(transaction.status.displayName)",
                        error: PaymentError.invalidTransaction,
                        pending: pending,
                        transaction: transaction)
        }
    }

    /// Dispatches a pending charge to either `processSale` (auth+capture
    /// in one call) or `preauthorize` (auth-only — capture happens
    /// separately via Transaction Details later) depending on which
    /// button was tapped on the review sheet.
    ///
    /// `preauthorize` returns a `TransactionResponse` so we unwrap to a
    /// `KoardTransaction` here; if for some reason there's no nested
    /// transaction we synthesize a minimal one with the response status
    /// so downstream code (`handleTransactionStatus`) still has
    /// something to dispatch on.
    private func runChargeAgainstSDK(pending: PendingSale) async throws -> KoardTransaction {
        let surcharge = appSettings.surchargeForSale()
        let taxRate: Double? = pending.taxCents > 0 ? appSettings.taxRatePercent : nil
        let tipAmount: Int? = pending.tipCents > 0 ? pending.tipCents : nil

        switch pending.flow {
        case .sale:
            return try await koardMerchantService.processSale(
                subtotal: pending.subtotalCents,
                taxAmount: pending.taxCents,
                taxRate: taxRate,
                tipAmount: tipAmount,
                tipRate: nil,
                tipType: .fixed,
                surcharge: surcharge
            )

        case .preauth:
            // Build the same breakdown shape processSale would have sent
            // so the gateway-side audit trail looks identical for the
            // two flows.
            let breakdown: PaymentBreakdown? = {
                let hasTax = pending.taxCents > 0
                let hasTip = pending.tipCents > 0
                let hasSurcharge = surcharge != nil
                guard hasTax || hasTip || hasSurcharge else { return nil }
                return PaymentBreakdown(
                    subtotal: pending.subtotalCents,
                    taxRate: taxRate,
                    taxAmount: pending.taxCents,
                    tipAmount: tipAmount,
                    tipRate: nil,
                    tipType: .fixed,
                    surcharge: surcharge
                )
            }()
            let response = try await koardMerchantService.preauthorize(
                amount: pending.totalCents,
                breakdown: breakdown,
                currency: CurrencyCode(currencyCode: "USD", displayName: nil)
            )
            if let tx = response.transaction { return tx }
            throw PaymentError.invalidTransaction
        }
    }

    private func defaultSurchargeDisclosure(rate: Double?) -> String {
        if let rate, rate > 0 {
            return "A \(String(format: "%.2f", rate))% surcharge will be applied to cover card processing fees. Do you accept?"
        }
        return "A surcharge will be applied to this transaction. Do you accept?"
    }

    // MARK: - Surcharge confirmation

    public func handleSurchargeDecision(confirm: Bool) async {
        // The prompt lives inside the current sheet now — pull it back
        // out rather than reading a separate property.
        guard case let .surcharge(prompt) = sheet else { return }
        let totalCentsSnapshot = prompt.totalCents
        isProcessing = true
        // Morph from .surcharge → .result(.processing) inside the same
        // sheet. Only on the Accept path; declines close everything
        // out at the bottom of this method.
        if confirm {
            sheet = .result(processingResultData(forTotalCents: totalCentsSnapshot))
        }
        defer {
            isProcessing = false
        }

        do {
            let updated = try await koardMerchantService.transactionConfirmed(
                transactionId: prompt.transactionId,
                confirm: confirm,
                amount: nil,
                breakdown: nil,
                eventId: nil
            )

            if updated.status == .authorized || updated.status == .captured {
                recordSuccess(transaction: updated, fallback: nil)
            } else if !confirm {
                // User declined — dismiss the sheet and clear the pad.
                sheet = nil
                amount.clear()
            } else {
                recordError("Transaction \(updated.status.displayName)",
                            error: PaymentError.invalidTransaction,
                            pending: nil,
                            transaction: updated)
            }
        } catch {
            // recordError() unwraps KoardMerchantSDKError / KoardDescribableError
            // internally, so one generic catch covers every error type here.
            recordError("Confirmation failed", error: error, pending: nil)
        }
    }

    // MARK: - Post-sale tip entry (restaurant flow)

    /// Customer hit Confirm on the tip entry sheet. Runs tipAdjust on
    /// the just-approved transaction, then surfaces the final receipt
    /// with the tip applied.
    public func tipEntryConfirmed(tipCents: Int) async {
        guard let transaction = transactionAwaitingTip else { return }
        let tipCents = max(0, tipCents)

        if tipCents == 0 {
            // No tip selected — skip the network round trip, just show
            // the original transaction as the final result.
            tipEntrySkipped()
            return
        }

        transactionAwaitingTip = nil
        isProcessing = true
        sheet = .result(processingResultData(forTotalCents: transaction.totalAmount + tipCents))
        defer { isProcessing = false }

        do {
            let response = try await koardMerchantService.tipAdjust(
                transactionId: transaction.transactionId,
                amount: tipCents,
                tipType: .fixed
            )
            // Prefer the server's returned transaction (has any updated
            // gateway response fields); fall back to mutating a copy of
            // the original if for some reason the wrapper doesn't have
            // one (shouldn't happen, but defensive).
            if let updated = response.transaction {
                presentFinalResult(transaction: updated)
            } else {
                presentFinalResult(transaction: transaction)
            }
            amount.clear()
        } catch {
            // recordError() unwraps KoardMerchantSDKError / KoardDescribableError
            // internally, so one generic catch covers every error type here.
            recordError("Tip adjust failed", error: error, pending: nil, transaction: transaction)
        }
    }

    /// Customer chose "No tip" — close out the flow with the original
    /// approved transaction as the final result, no tipAdjust call made.
    public func tipEntrySkipped() {
        guard let transaction = transactionAwaitingTip else { return }
        transactionAwaitingTip = nil
        presentFinalResult(transaction: transaction)
        amount.clear()
    }

    // MARK: - Partial approval continuation

    /// Called when the user taps "Tap for remaining $X" on the result
    /// sheet. Fires a fresh charge for the remainder amount, repeating
    /// the same flow type (sale vs preauth) the original charge used.
    /// Subsequent partial approvals chain naturally — each result sheet
    /// surfaces the remainder of the LAST attempt.
    public func continuePartialApproval() {
        guard let remainder = partialApprovalRemainder, remainder > 0 else { return }
        let flow = partialApprovalFlow ?? .sale

        // Reset the remainder so a fast double-tap doesn't fire twice.
        partialApprovalRemainder = nil
        partialApprovalFlow = nil

        // We charge the leftover as a pure amount, no tax/tip/subtotal
        // breakdown — the gateway-side breakdown was already captured
        // by the first partial. The second tap is "settle the rest".
        let pending = PendingSale(
            subtotalCents: remainder,
            taxCents: 0,
            tipCents: 0,
            surchargeCents: 0,
            flow: flow
        )
        pendingSale = pending
        Task { await runPendingSale() }
    }

    // MARK: - Result sheet dismissal

    public func resultSheetDismissed() {
        sheet = nil
        partialApprovalRemainder = nil
        partialApprovalFlow = nil
    }

    // MARK: - Location

    public func fetchLocations() async {
        availableLocations = []
        isLoadingLocations = true
        defer { isLoadingLocations = false }
        do {
            let refreshed = try await koardMerchantService.fetchLocations()
            try Task.checkCancellation()
            availableLocations = refreshed
        } catch { print("[Register] Location refresh failed: \(error.localizedDescription)") }
    }

    public func selectLocation(_ location: Location) {
        koardMerchantService.updateLocation(location: location)
        selectedLocation = location
        readerState.noteLocationChanged()
    }

    public func refreshActiveLocation() async {
        if let refreshed = await koardMerchantService.loadActiveLocation() {
            selectedLocation = refreshed
        }
    }

    // MARK: - Helpers

    private func recordSuccess(transaction: KoardTransaction, fallback: PendingSale?) {
        // RESTAURANT FLOW INTERCEPT
        // If the active mode is Restaurant/Bar AND tip is enabled AND the
        // returned transaction doesn't already have a tip on it, route to
        // the post-sale tip entry sheet instead of showing the final
        // receipt. tipEntryConfirmed / tipEntrySkipped will land us back
        // in `presentFinalResult` with the updated transaction.
        //
        // We use a separate `transactionAwaitingTip != nil` guard to make
        // sure recordSuccess being called twice (e.g. surcharge confirm
        // re-running through the same path) can't loop us back into tip
        // entry.
        if appSettings.checkoutMode == .restaurantBar,
           appSettings.tipEnabled,
           transaction.tipAmount == 0,
           transactionAwaitingTip == nil {
            // Prefer the fresh-sale fallback so subtotal/tax exactly
            // match what we sent; fall back to the transaction's fields
            // for the surcharge-confirm path where there's no fallback.
            let subtotal = fallback?.subtotalCents ?? transaction.subtotal
            let taxCents = fallback?.taxCents ?? transaction.taxAmount
            transactionAwaitingTip = transaction
            sheet = .tipEntry(.init(
                transactionId: transaction.transactionId,
                currency: transaction.currency,
                subtotalCents: subtotal,
                taxCents: taxCents,
                chargedTotalCents: transaction.totalAmount
            ))
            return
        }
        presentFinalResult(transaction: transaction)
    }

    /// Build and present the settled "approved" result sheet for a
    /// completed transaction. Called either directly from a Retail sale,
    /// or from the Restaurant flow after tipAdjust returns. Clears the
    /// pin-pad amount so the cashier starts fresh when they dismiss.
    ///
    /// Branches on `transaction.isPartiallyApproved` so a partial auth
    /// from the issuer shows up as a `.partiallyApproved` outcome with
    /// a "Tap for remaining $X" button instead of a plain "Approved".
    private func presentFinalResult(transaction: KoardTransaction) {
        amount.clear()
        let currency = CurrencyCode(currencyCode: transaction.currency, displayName: nil)
        let partial = transaction.isPartiallyApproved
        let remainingCents = transaction.partialApprovalRemainingCents
        sheet = .result(.init(
            outcome: partial ? .partiallyApproved : .approved,
            title: partial ? "Partially approved" : "Approved",
            // Surface the amount the issuer ACTUALLY authorized as the
            // "Total" — that's what the customer was charged.
            total: MoneyUtils.centsToStringWithCurrency(transaction.displayedTotalCents, currency: currency),
            remainingAmount: partial
                ? MoneyUtils.centsToStringWithCurrency(remainingCents, currency: currency)
                : nil,
            subtotal: nonZeroMoney(transaction.subtotal, currency: currency),
            tax: nonZeroMoney(transaction.taxAmount, currency: currency),
            tip: nonZeroMoney(transaction.tipAmount, currency: currency),
            surcharge: surchargeMoney(transaction: transaction, currency: currency),
            surchargeRate: surchargeRateForReceipt(transaction: transaction),
            card: transaction.card,
            cardBrand: transaction.cardBrand,
            transactionId: transaction.transactionId,
            status: transaction.status.displayName,
            statusReason: transaction.statusReason,
            approvalCode: transaction.gatewayTransactionResponse?.approvalCode,
            processorResponseCode: transaction.processorResponseCode
                ?? transaction.gatewayTransactionResponse?.processorResponseCode
                ?? transaction.gatewayTransactionResponse?.responseCode,
            processorResponseMessage: transaction.processorResponseMessage,
            gatewayResponseMessage: transaction.gatewayTransactionResponse?.responseMessage
        ))
        // Stash the remaining-balance amount so the result sheet's
        // "Tap for remaining $X" button has somewhere to dispatch to.
        partialApprovalRemainder = partial ? remainingCents : nil
        partialApprovalFlow = partial ? lastChargeFlow : nil
    }

    /// Gateway returned a `pending` status — the transaction was accepted
    /// but not finalized. We still show the receipt (the cashier knows
    /// the customer's card was tapped successfully) but with a Pending
    /// outcome so they don't treat it as a confirmed sale yet.
    private func recordPending(transaction: KoardTransaction) {
        amount.clear()
        let currency = CurrencyCode(currencyCode: transaction.currency, displayName: nil)
        sheet = .result(.init(
            outcome: .pending,
            title: "Pending",
            total: MoneyUtils.centsToStringWithCurrency(transaction.totalAmount, currency: currency),
            subtotal: nonZeroMoney(transaction.subtotal, currency: currency),
            tax: nonZeroMoney(transaction.taxAmount, currency: currency),
            tip: nonZeroMoney(transaction.tipAmount, currency: currency),
            surcharge: surchargeMoney(transaction: transaction, currency: currency),
            surchargeRate: surchargeRateForReceipt(transaction: transaction),
            card: transaction.card,
            cardBrand: transaction.cardBrand,
            transactionId: transaction.transactionId,
            status: transaction.status.displayName,
            statusReason: transaction.statusReason
                ?? "The gateway is still processing this transaction. Check History → Detail later for the settled state.",
            approvalCode: transaction.gatewayTransactionResponse?.approvalCode,
            processorResponseCode: transaction.processorResponseCode
                ?? transaction.gatewayTransactionResponse?.processorResponseCode
                ?? transaction.gatewayTransactionResponse?.responseCode,
            processorResponseMessage: transaction.processorResponseMessage,
            gatewayResponseMessage: transaction.gatewayTransactionResponse?.responseMessage
        ))
    }

    private func recordDeclined(transaction: KoardTransaction, fallback: PendingSale) {
        let currency = CurrencyCode(currencyCode: transaction.currency, displayName: nil)
        sheet = .result(.init(
            outcome: .declined,
            title: "Declined",
            total: MoneyUtils.centsToStringWithCurrency(transaction.totalAmount, currency: currency),
            subtotal: nonZeroMoney(transaction.subtotal, currency: currency),
            tax: nonZeroMoney(transaction.taxAmount, currency: currency),
            tip: nonZeroMoney(transaction.tipAmount, currency: currency),
            surcharge: surchargeMoney(transaction: transaction, currency: currency),
            surchargeRate: surchargeRateForReceipt(transaction: transaction),
            card: transaction.card,
            cardBrand: transaction.cardBrand,
            transactionId: transaction.transactionId,
            status: transaction.status.displayName,
            statusReason: transaction.statusReason ?? transaction.processorResponseMessage,
            approvalCode: transaction.gatewayTransactionResponse?.approvalCode,
            processorResponseCode: transaction.processorResponseCode
                ?? transaction.gatewayTransactionResponse?.processorResponseCode
                ?? transaction.gatewayTransactionResponse?.responseCode,
            processorResponseMessage: transaction.processorResponseMessage,
            gatewayResponseMessage: transaction.gatewayTransactionResponse?.responseMessage
        ))
    }

    /// Customer cancelled at the Apple TTP sheet. No transaction was created
    /// on the gateway/processor side so there's nothing to show beyond the
    /// fact that the cashier needs to start over.
    private func recordCancelled(pending: PendingSale) {
        sheet = .result(.init(
            outcome: .cancelled,
            title: "Cancelled",
            total: MoneyUtils.centsToStringWithCurrency(pending.totalCents),
            subtotal: nil, tax: nil, tip: nil, surcharge: nil,
            card: nil, cardBrand: nil,
            transactionId: nil,
            status: "Cancelled",
            statusReason: "Cancelled at the reader."
        ))
    }

    private func recordError(
        _ title: String,
        error: Error,
        pending: PendingSale?,
        transaction: KoardTransaction? = nil
    ) {
        let totalCents = transaction?.totalAmount ?? pending?.totalCents ?? amount.cents
        // Detail line: prefer the SDK's human-readable message, then the
        // transaction's own status reason, then a generic description.
        let detail: String
        // `PaymentError.invalidTransaction` is a generic placeholder we raise for
        // terminal gateway states (.error/.timedOut/.pickupCard/.reversed/
        // .refunded/.unknown, and surcharge-confirm mismatches). The transaction
        // itself carries the specific gateway reason, so prefer that over the
        // generic "Invalid transaction" text in those cases.
        if let paymentError = error as? PaymentError, case .invalidTransaction = paymentError,
           let reason = transaction?.statusReason, !reason.isEmpty {
            detail = reason
        } else if let describable = error as? KoardDescribableError {
            detail = describable.errorDescription
        } else if let reason = transaction?.statusReason, !reason.isEmpty {
            detail = reason
        } else {
            detail = error.localizedDescription
        }
        sheet = .result(.init(
            outcome: .error,
            title: title,
            total: MoneyUtils.centsToStringWithCurrency(totalCents),
            subtotal: nil, tax: nil, tip: nil, surcharge: nil,
            card: transaction?.card,
            cardBrand: transaction?.cardBrand,
            transactionId: transaction?.transactionId,
            status: transaction?.status.displayName ?? "Error",
            statusReason: detail,
            approvalCode: transaction?.gatewayTransactionResponse?.approvalCode,
            processorResponseCode: transaction?.processorResponseCode
                ?? transaction?.gatewayTransactionResponse?.processorResponseCode
                ?? transaction?.gatewayTransactionResponse?.responseCode,
            processorResponseMessage: transaction?.processorResponseMessage,
            gatewayResponseMessage: transaction?.gatewayTransactionResponse?.responseMessage
        ))
        print("[PinPadViewModel] sale error: \(error)")
    }

    private func nonZeroMoney(_ cents: Int, currency: CurrencyCode) -> String? {
        cents > 0 ? MoneyUtils.centsToStringWithCurrency(cents, currency: currency) : nil
    }

    /// Surcharge amount string for the receipt. Skips the row when the
    /// gateway reports no surcharge was applied to this transaction, even
    /// if surchargeAmount happens to be non-nil-but-zero.
    private func surchargeMoney(transaction: KoardTransaction, currency: CurrencyCode) -> String? {
        guard transaction.surchargeApplied, let cents = transaction.surchargeAmount, cents > 0 else {
            return nil
        }
        return MoneyUtils.centsToStringWithCurrency(cents, currency: currency)
    }

    /// Surcharge rate for the receipt row label ("Surcharge (3%)"). Only
    /// returned when both the rate and the applied flag are present.
    private func surchargeRateForReceipt(transaction: KoardTransaction) -> Double? {
        guard transaction.surchargeApplied, let rate = transaction.surchargeRate, rate > 0 else {
            return nil
        }
        return rate
    }

    /// Build the "processing" view of the result sheet. Shown immediately
    /// when a sale fires so the user has continuous feedback while the
    /// gateway round trip is in flight. The sheet swaps in-place to the
    /// settled outcome when the response comes back.
    private func processingResultData(forTotalCents totalCents: Int) -> SaleResultSheet.ResultData {
        SaleResultSheet.ResultData(
            outcome: .processing,
            title: "Processing…",
            total: MoneyUtils.centsToStringWithCurrency(totalCents),
            subtotal: nil, tax: nil, tip: nil, surcharge: nil,
            card: nil, cardBrand: nil,
            transactionId: nil,
            status: "Waiting for gateway response",
            statusReason: nil
        )
    }

    /// True iff `sdkError` represents "the reader wasn't actually set up"
    /// rather than "the customer's card was declined / the sale failed
    /// after the tap." We only re-pop the preparing modal for the former
    /// — the latter is a legitimate result that the user needs to see.
    ///
    /// `TTPConfigurationFailed(...)` covers: no reader, no PSP token,
    /// account-linking error, device-configuration failed, not
    /// authenticated. All "preparing failed" symptoms. `TTPPaymentFailed`
    /// is intentionally NOT included — that fires for actual sale
    /// outcomes (declined card, read cancelled, etc.) which belong in the
    /// result sheet, not the preparing modal.
    private func isReaderNotReady(_ sdkError: KoardMerchantSDKError) -> Bool {
        if case .TTPConfigurationFailed = sdkError { return true }
        return false
    }

    /// Thin wrapper over the shared `KoardMerchantSDKError.isReaderCancellation`
    /// so existing call sites read unchanged. See that extension for the logic.
    private func isCancellation(_ sdkError: KoardMerchantSDKError) -> Bool {
        sdkError.isReaderCancellation
    }
}

extension KoardMerchantSDKError {
    /// True iff this represents "customer cancelled at the Apple Tap-to-Pay
    /// sheet" — the explicit `.canceled` case, or any `paymentCardReaderError`
    /// whose underlying description contains "cancel" (fuzzy fallback so we
    /// still catch Apple's "Read operation cancelled" / "PIN entry cancelled"
    /// variants without relying on new typed cases).
    ///
    /// Shared by `PinPadViewModel` (tap sales) and `TransactionDetailsViewModel`
    /// (tap refunds / partial completion) so a reader cancel is treated as a
    /// benign `.cancelled` in both, not a generic failure.
    var isReaderCancellation: Bool {
        guard case let .TTPPaymentFailed(ttpError) = self else { return false }
        if case .canceled = ttpError { return true }
        guard case let .paymentCardReaderError(underlying) = ttpError else { return false }
        let description = String(describing: underlying).lowercased()
        if description.contains("cancel") { return true }
        if let localized = (underlying as? CustomStringConvertible)?.description.lowercased(),
           localized.contains("cancel") {
            return true
        }
        if (underlying as NSError).localizedDescription.lowercased().contains("cancel") {
            return true
        }
        return false
    }
}

extension PinPadViewModel: Hashable {
    public nonisolated static func == (lhs: PinPadViewModel, rhs: PinPadViewModel) -> Bool {
        lhs.id == rhs.id
    }

    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
