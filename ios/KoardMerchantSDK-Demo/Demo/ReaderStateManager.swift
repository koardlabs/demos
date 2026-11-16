import Foundation
import KoardSDK
import SwiftUI
#if canImport(ProximityReader)
import ProximityReader
#endif

/// Mirror of the SDK's card reader state, exposed as `@Observable` so the
/// demo UI can react to it.
///
/// **Why polling instead of subscribing to `KoardMerchantSDK.shared.readerEvents`?**
///
/// The SDK's `ProximityReaderViewModel` already owns and iterates the
/// `PaymentCardReader.events` AsyncStream internally — it's the *one*
/// subscriber that drives the SDK's own status enum. If the demo also
/// subscribes, the two iterators race for delivered values and one of
/// them silently loses events.
///
/// The SDK's status enum already covers everything we need:
///
/// ```
/// .notReady              → .idle  (or .preparing if a prepare task is in-flight)
/// .preparing             → .preparing
/// .configuring(progress) → .preparing (with progress 0..100)
/// .linked / .ready       → .ready
/// .cardReaderError(err)  → .failed(err.localizedDescription)
/// .error(err)            → .failed(err.localizedDescription)
/// ```
///
/// **Performance notes.** Two things were hammering the main thread in the
/// previous version of this file:
///
/// 1. `koardMerchantService.isAuthenticated` and `isReaderSetupSupported`
///    each hit the Keychain (via `SecItemCopyMatching`), which is
///    surprisingly slow on real devices (1–5 ms per call). We were
///    calling them 4× per second.
/// 2. The poll cadence was 250 ms regardless of state — overkill when the
///    reader is just sitting at `.ready`.
///
/// Both fixed below: auth flags are cached and only refreshed on explicit
/// lifecycle hooks (login, logout, foreground), and polling is adaptive —
/// fast (200 ms) only while preparing, slow (1.5 s) the rest of the time.
@MainActor
@Observable
public final class ReaderStateManager {
    public enum State: Equatable, CustomStringConvertible {
        case idle
        case preparing
        case ready
        case unsupported
        case failed(message: String)

        public var description: String {
            switch self {
            case .idle: return "idle"
            case .preparing: return "preparing"
            case .ready: return "ready"
            case .unsupported: return "unsupported"
            case let .failed(message): return "failed(\(message))"
            }
        }

        public var isReady: Bool {
            if case .ready = self { return true }
            return false
        }

        public var isPreparing: Bool {
            if case .preparing = self { return true }
            return false
        }

        public var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    public private(set) var state: State = .idle
    public private(set) var progress: Int = 0
    public private(set) var preparedAt: Date?
    /// Short human-readable description of the latest snapshot — used by
    /// the preparing modal for triage. Not assigned every tick; only when
    /// it actually changes.
    public private(set) var lastEventDescription: String = ""

    /// True when the SDK reports the Tap to Pay account isn't linked yet —
    /// `prepare()` throws `.accountNotLinked` instead of auto-presenting Apple's
    /// linking sheet. The UI (Settings row + the PIN pad "Accept T&C" button)
    /// observes this to offer linking on the merchant's terms. We never
    /// auto-link, so declining no longer re-prompts on every launch.
    public private(set) var needsAccountLinking: Bool = false

    @ObservationIgnored private let koardMerchantService: KoardMerchantServiceable
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private var lastRecordedStatusKey: String = ""

    /// Marks a window during which a transient reader error should be
    /// reported as `.preparing` rather than `.failed`.
    ///
    /// **Why this exists.** Changing the active location does NOT re-prepare
    /// through `ensureReady`/`inFlight`. `KoardMerchantService.updateLocation`
    /// tears down the old location's reader session and kicks off its own
    /// internal prepare (getToken → linkAccount → prepare) directly against
    /// the SDK. From this manager's point of view `inFlight` is `nil` the
    /// whole time, so the brief torn-down-session error the SDK reports while
    /// that internal prepare spins up would otherwise surface as `.failed`
    /// ("Card reader unavailable" + Retry) even though a recovery is actively
    /// in progress. Setting this on a location change keeps the UI on
    /// `.preparing` until the reader comes back (cleared on `.ready`) or the
    /// window lapses (so a genuine, persistent failure still surfaces).
    @ObservationIgnored private var recoveringUntil: Date?

    /// True while the merchant is on Apple's account-linking (T&C) sheet driven
    /// by `linkAccount()`. Linking is a user-driven step, NOT reader prep — so
    /// while it's set, `map` reports `.idle` (the link CTA) instead of
    /// synthesizing `.preparing`/`.failed` from the SDK's transient
    /// `.notReady`/error. Without this, DECLINING the sheet flashed
    /// "Preparing card reader…" before settling back to the CTA.
    @ObservationIgnored private var isLinking = false

    /// Cached snapshots of the two Keychain-hitting flags. Refreshed only
    /// on explicit lifecycle events (init, login success, logout,
    /// foreground) — NOT on every poll tick. This is the single biggest
    /// perf win in this file.
    @ObservationIgnored private var cachedIsAuthenticated: Bool = false
    @ObservationIgnored private var cachedIsReaderSetupSupported: Bool = false

    /// Adaptive poll cadence. Tight while preparing so the progress bar
    /// feels live; loose otherwise so we're not burning main-thread cycles
    /// for nothing.
    private static let preparingPollInterval: TimeInterval = 0.2
    private static let idlePollInterval: TimeInterval = 1.5

    /// How long after a location change we keep treating a transient reader
    /// error as `.preparing`. Comfortably covers the SDK's internal
    /// getToken → linkAccount → prepare round trip; once the reader has
    /// actually dropped and come back `.ready` the window is cleared early,
    /// and a failure that outlasts the window falls through to `.failed` so
    /// the user can retry.
    private static let locationRecoveryWindow: TimeInterval = 30

    /// Set true once we've observed the reader actually leave `.ready` during
    /// a recovery window.
    ///
    /// **Why this is needed.** `updateLocation` tears the old session down
    /// *asynchronously*, so at the instant `noteLocationChanged()` fires the
    /// SDK is usually still reporting the OLD location's `.ready`. Without
    /// this guard the very first `syncFromSDK()` would see that stale
    /// `.ready` and immediately clear the recovery window — then the teardown
    /// lands a beat later and surfaces as `.failed`, which is exactly the bug
    /// this whole mechanism exists to prevent. We only clear the window once
    /// the reader has genuinely dropped and returned to `.ready`.
    @ObservationIgnored private var sawSessionDropSinceLocationChange = false

    /// True while we're inside the post-location-change recovery window.
    private var isRecoveringSession: Bool {
        guard let recoveringUntil else { return false }
        return recoveringUntil > Date()
    }

    public init(koardMerchantService: KoardMerchantServiceable) {
        self.koardMerchantService = koardMerchantService
        refreshAuthSnapshot()
        syncFromSDK()
        startPolling()
    }

    deinit {
        pollTask?.cancel()
        inFlight?.cancel()
    }

    // MARK: - Public surface

    /// Kick off a prepare against the SDK. Coalesces with any in-flight
    /// prepare. The poll loop is what surfaces progress / completion to
    /// the UI.
    public func ensureReady(force: Bool = false) {
        refreshAuthSnapshot()
        guard cachedIsAuthenticated else {
            applyState(.idle, progress: 0)
            return
        }
        guard cachedIsReaderSetupSupported else {
            applyState(.unsupported, progress: 0)
            return
        }
        if let inFlight, !inFlight.isCancelled { return }
        _ = force // (parameter kept for source compat)
        // IMPORTANT: Task.detached, NOT Task { ... }.
        //
        // ReaderStateManager is @MainActor-isolated, so a plain `Task { }`
        // inherits MainActor isolation and the SDK's prepare work runs on
        // the main thread. Apple's TTP prepare path has chunks of
        // synchronous CPU between awaits (cryptographic setup, keychain
        // hits) that block the run loop and noticeably lag the user's
        // first keystrokes on a cold launch.
        //
        // A detached task runs on the cooperative pool instead, leaving
        // the main thread free for the keypad. We hop back to MainActor
        // only for the small writes to `preparedAt` and `inFlight`.
        let service = koardMerchantService
        inFlight = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await service.prepareCardReader()
                await MainActor.run {
                    self?.preparedAt = Date()
                    self?.needsAccountLinking = false
                }
            } catch KoardMerchantSDKError.accountNotLinked {
                // prepare() no longer auto-links — surface it so the UI can
                // offer "Accept T&C" / link, instead of re-presenting Apple's
                // account-linking sheet on every launch.
                await MainActor.run { self?.needsAccountLinking = true }
            } catch {
                print("[ReaderStateManager] prepare threw: \(error)")
            }
            await MainActor.run {
                self?.inFlight = nil
                self?.syncFromSDK()
            }
        }
        // `inFlight` is now set, so re-evaluate immediately: this flips a
        // stale `.failed` (e.g. after a location change) to `.preparing`
        // on this run-loop tick instead of waiting up to 1.5s for the next
        // slow idle poll, which is what made the error linger on screen.
        syncFromSDK()
    }

    /// Link the merchant's Tap to Pay account, then prepare the reader.
    /// Called from the UI's explicit link controls (Settings row / the PIN pad
    /// "Accept T&C" button). `prepare()` intentionally does NOT auto-link, so
    /// this is the one place linking is initiated — on the merchant's action.
    public func linkAccount() {
        refreshAuthSnapshot()
        guard cachedIsAuthenticated else { return }
        if let inFlight, !inFlight.isCancelled { return }
        let service = koardMerchantService
        isLinking = true
        inFlight = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await service.linkAccount()
                // The SDK's linkAccountAsync() SWALLOWS a declined/failed link
                // (updates reader status but never rethrows), so "returned" does
                // NOT tell us whether linking happened. Ask the SDK directly:
                //  • ACCEPT  → clear needsAccountLinking immediately so the shared
                //    state updates the main view reactively (no tab-nav needed),
                //    then prepare the reader.
                //  • DECLINE → leave needsAccountLinking set so the CTA stays put
                //    with no "not linked → idle → not linked" flash.
                var linked = false
                if #available(iOS 17.0, *) {
                    linked = (try? await KoardMerchantSDK.shared.isAccountLinked()) ?? false
                }
                // If this task was cancelled (e.g. logout's reset() cancels
                // inFlight), stop before touching shared state — otherwise a link
                // started before logout could restore needsAccountLinking /
                // preparedAt for the NEXT session's reader.
                if Task.isCancelled { return }
                await MainActor.run { self?.isLinking = false }
                if linked {
                    await MainActor.run { self?.needsAccountLinking = false }
                    try await service.prepareCardReader()
                    if Task.isCancelled { return }
                    await MainActor.run { self?.preparedAt = Date() }
                } else {
                    await MainActor.run { self?.needsAccountLinking = true }
                }
            } catch KoardMerchantSDKError.accountNotLinked {
                if !Task.isCancelled { await MainActor.run { self?.needsAccountLinking = true } }
            } catch {
                // Includes the merchant DECLINING Apple's sheet — not a reader
                // failure to surface; we just fall back to the link CTA.
                print("[ReaderStateManager] linkAccount threw: \(error)")
            }
            // Skip the reconcile if cancelled — reset() already cleared inFlight
            // and neutralized the flags for the next session.
            if Task.isCancelled { return }
            await MainActor.run {
                self?.isLinking = false
                self?.inFlight = nil
                self?.syncFromSDK()
            }
        }
        // No optimistic `.preparing`: presenting Apple's T&C sheet isn't reader
        // prep, and showing it flashed "Preparing…" on decline. `isLinking`
        // keeps the UI on the CTA until linking actually succeeds.
        syncFromSDK()
    }

    /// Called from `scenePhase` becoming `.active`. Re-syncs immediately,
    /// then triggers a prepare if SDK status looks idle/failed.
    public func handleAppDidBecomeActive() {
        refreshAuthSnapshot()
        syncFromSDK()
        switch state {
        case .idle, .failed:
            ensureReady(force: true)
        default:
            break
        }
    }

    /// Call when the active location has just changed. The SDK is now
    /// tearing down the old reader session and re-preparing a new one
    /// internally (see `KoardMerchantService.updateLocation`) — work that
    /// never flows through `inFlight`. Open a recovery window so the UI shows
    /// `.preparing` instead of the stale session's `.failed`, and flip the
    /// state immediately (the next poll would otherwise leave the error on
    /// screen for up to a full slow-poll interval).
    public func noteLocationChanged() {
        recoveringUntil = Date().addingTimeInterval(Self.locationRecoveryWindow)
        // Reset: we have NOT yet seen the (asynchronous) teardown. The window
        // must survive the stale pre-teardown `.ready` reading.
        sawSessionDropSinceLocationChange = false
        progress = 0
        syncFromSDK()
    }

    public var statusLine: String {
        switch state {
        case .idle: return "Card reader idle"
        case .preparing:
            if progress > 0 { return "Preparing card reader… \(progress)%" }
            return "Preparing card reader…"
        case .ready: return "Card reader ready"
        case .unsupported: return "Tap to Pay not supported on this device"
        case let .failed(message): return "Card reader unavailable — \(message)"
        }
    }

    public func reset() {
        inFlight?.cancel()
        inFlight = nil
        state = .idle
        progress = 0
        preparedAt = nil
        // A logged-out session has no known linked/linking state — neutralize
        // both so the next merchant's prepare determines them fresh (and a
        // logout mid-link doesn't leave the CTA stuck).
        needsAccountLinking = false
        isLinking = false
        lastEventDescription = ""
        lastRecordedStatusKey = ""
        recoveringUntil = nil
        sawSessionDropSinceLocationChange = false
        cachedIsAuthenticated = false
        cachedIsReaderSetupSupported = false
    }

    // MARK: - Auth caching

    /// Single-shot Keychain hit. Called on init, foreground, login, logout
    /// — NOT on every poll tick.
    private func refreshAuthSnapshot() {
        cachedIsAuthenticated = koardMerchantService.isAuthenticated
        cachedIsReaderSetupSupported = koardMerchantService.isReaderSetupSupported
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = await Self.intervalFor(self)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                await self?.syncFromSDK()
            }
        }
    }

    private static func intervalFor(_ manager: ReaderStateManager?) async -> TimeInterval {
        await MainActor.run {
            // Poll fast throughout the recovery window even while the state is
            // still the stale `.ready`, so the asynchronous teardown is caught
            // promptly instead of up to a full slow interval later.
            if manager?.isRecoveringSession == true { return preparingPollInterval }
            switch manager?.state {
            case .preparing: return preparingPollInterval
            default: return idlePollInterval
            }
        }
    }

    /// Snapshot `KoardMerchantSDK.shared.status` and translate it into our
    /// own `State` enum. Idempotent — only assigns to our `@Observable`
    /// properties when the value actually changes.
    ///
    /// Reads the cached `isAuthenticated` / `isReaderSetupSupported` snapshot
    /// to avoid hitting Keychain on every tick.
    private func syncFromSDK() {
        guard cachedIsAuthenticated else {
            applyState(.idle, progress: 0, key: "unauth")
            return
        }
        guard cachedIsReaderSetupSupported else {
            applyState(.unsupported, progress: 0, key: "unsupported")
            return
        }

        #if canImport(ProximityReader)
        if #available(iOS 17.0, *) {
            let sdkStatus = KoardMerchantSDK.shared.status
            let (next, nextProgress, key, label) = map(sdkStatus)
            // Starting a fresh prepare cycle (the reader just left `.ready`):
            // don't carry the finished prepare's stale 100% into the new cycle —
            // start the bar at 0 so it counts up cleanly. Without this, a location
            // switch flashed "…100%" for a blip, because map()'s `max(progress, 1)`
            // resurrected the previous prepare's 100 until real progress arrived.
            let freshProgress = (state == .ready && next == .preparing) ? 0 : nextProgress
            applyState(next, progress: freshProgress, key: key)
            if label != lastEventDescription {
                lastEventDescription = label
            }
            // Track the reader actually leaving `.ready` during recovery so a
            // stale pre-teardown `.ready` can't close the window prematurely.
            if isRecoveringSession, next != .ready {
                sawSessionDropSinceLocationChange = true
            }
            if next == .ready {
                if preparedAt == nil { preparedAt = Date() }
                // Reader is ready => account is linked; clear any stale prompt.
                if needsAccountLinking { needsAccountLinking = false }
                // Close the window only once the reader has genuinely dropped
                // and come back — NOT on the stale `.ready` that's still being
                // reported the instant a location change is requested.
                if sawSessionDropSinceLocationChange {
                    recoveringUntil = nil
                    sawSessionDropSinceLocationChange = false
                }
            }
            return
        }
        #endif

        applyState(.unsupported, progress: 0, key: "no-proximity")
    }

    private func applyState(_ next: State, progress nextProgress: Int, key: String = "") {
        let clamped = max(0, min(100, nextProgress))
        if !key.isEmpty, key == lastRecordedStatusKey,
           state == next, progress == clamped {
            return // unchanged, skip assignment to avoid view churn
        }
        lastRecordedStatusKey = key
        if state != next { state = next }
        if progress != clamped { progress = clamped }
    }

    #if canImport(ProximityReader)
    @available(iOS 17.0, *)
    private func map(_ status: ProximityReaderStatus) -> (State, Int, String, String) {
        // While the merchant is on Apple's account-linking sheet, keep the UI on
        // the idle/link CTA — don't interpret the SDK's transient `.notReady`/
        // error as reader `.preparing`/`.failed` (that flashed "Preparing…" on
        // decline). Once linking succeeds `isLinking` is cleared and the ensuing
        // prepare surfaces normally.
        if isLinking {
            return (.idle, 0, "linking", "Linking account…")
        }
        switch status {
        case .notReady:
            if inFlight != nil || isRecoveringSession {
                return (.preparing, max(progress, 1), "notReady+inflight", "Reader spinning up…")
            }
            return (.idle, 0, "notReady", "Not ready")

        case .preparing:
            return (.preparing, max(progress, 1), "preparing", "Preparing")

        case let .configuring(value):
            return (.preparing, value, "configuring-\(value)", "Configuring \(value)%")

        case .linked, .ready:
            return (.ready, 100, "ready", "Ready for tap")

        case let .cardReaderError(error):
            // A prepare in flight means we're actively recovering — e.g. the
            // user changed location, which invalidates the old reader session
            // and makes the SDK briefly report the stale session's error
            // before the new prepare takes hold. Surface that as `.preparing`
            // so checkout shows the progress spinner, not a scary error.
            // Only report `.failed` once no prepare is running to recover it.
            // `isRecoveringSession` covers the location-change case, where the
            // recovering prepare runs inside the SDK and never touches
            // `inFlight` (see `noteLocationChanged`).
            if inFlight != nil || isRecoveringSession {
                return (.preparing, max(progress, 1), "cardReaderError+inflight", "Re-preparing reader…")
            }
            return (.failed(message: error.localizedDescription), 0,
                    "cardReaderError", "Card reader error: \(error.localizedDescription)")

        case let .error(error):
            if inFlight != nil || isRecoveringSession {
                return (.preparing, max(progress, 1), "error+inflight", "Re-preparing reader…")
            }
            return (.failed(message: error.localizedDescription), 0,
                    "error", "Reader error: \(error.localizedDescription)")
        }
    }
    #endif
}
