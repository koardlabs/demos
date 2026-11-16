import Foundation
import KoardSDK
import SwiftUI

/// Persisted user-facing preferences for the demo app.
///
/// Stored in `UserDefaults` so they survive launches and don't need to be
/// threaded through the view hierarchy. The class is `@Observable` so views
/// that read its properties auto-update on changes.
@MainActor
@Observable
public final class AppSettings {
    public static let shared = AppSettings()

    public enum CheckoutMode: String, CaseIterable, Identifiable, Hashable {
        case retail
        case restaurantBar
        case legacy

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .retail: return "Retail"
            case .restaurantBar: return "Restaurant / Bar"
            case .legacy: return "Legacy form"
            }
        }

        public var description: String {
            switch self {
            case .retail:
                return "Pin-pad enters the amount. Charge opens a review sheet with tax + tip, then runs the sale."
            case .restaurantBar:
                return "Pin-pad enters the subtotal. Charge opens a customer-facing handoff with tax + tip selection, then runs the sale."
            case .legacy:
                return "The original tax / tip / surcharge form view from earlier builds."
            }
        }
    }

    /// How the demo should populate the `surcharge` field on outgoing
    /// `processSale` calls. The SDK contract on `PaymentBreakdown.Surcharge?`:
    ///
    /// - `nil`                     → "do whatever the account is configured to do"
    /// - `Surcharge(bypass: true)` → never apply a surcharge on this sale
    /// - `Surcharge(percentage:N)` → override account default with this rate
    ///
    /// The legacy demo screen had this exposed as two toggles ("override"
    /// and "bypass"). We collapse it down to a single three-way picker
    /// here since the new flows are all-app-wide and need ONE answer.
    public enum SurchargeMode: String, CaseIterable, Identifiable, Hashable {
        /// Don't send a `surcharge` field at all — let whatever the
        /// merchant account is set up to do happen. This is the safe
        /// default for new users and what the demo was hardcoded to
        /// before this setting existed.
        case accountDefault
        /// Always send `Surcharge(bypass: true)`. Useful when an
        /// account has surcharge on but the cashier doesn't want it for
        /// a particular run (e.g. they're absorbing fees).
        case disabled
        /// Always send `Surcharge(percentage: surchargeOverrideRate)`.
        /// Lets the cashier pin the rate explicitly.
        case overridePercent

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .accountDefault: return "Default"
            case .disabled: return "Disabled"
            case .overridePercent: return "Override rate"
            }
        }

        public var description: String {
            switch self {
            case .accountDefault:
                return "Don't send a surcharge field. The Koard merchant account configuration decides what happens."
            case .disabled:
                return "Never apply a surcharge. The SDK is told to bypass on every sale."
            case .overridePercent:
                return "Override the account default with the percentage below."
            }
        }
    }

    public enum AppearanceMode: String, CaseIterable, Identifiable, Hashable {
        case system
        case light
        case dark

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        public var preferredColorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    /// Which checkout flow the user wants on the main tab.
    public var checkoutMode: CheckoutMode {
        get { CheckoutMode(rawValue: checkoutModeRaw) ?? .retail }
        set { checkoutModeRaw = newValue.rawValue }
    }

    /// Force light, force dark, or follow the system.
    public var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    /// When ON, the configured `taxRatePercent` is added to every charge.
    /// Applies to ALL pin-pad flows (Retail and Restaurant/Bar).
    public var taxEnabled: Bool {
        didSet { UserDefaults.standard.set(taxEnabled, forKey: Self.taxEnabledKey) }
    }

    /// Tax rate in percent (e.g. 8.25 means 8.25%). Only used when
    /// `taxEnabled` is true. Capped at 100% for sanity.
    public var taxRatePercent: Double {
        didSet {
            let clamped = max(0, min(100, taxRatePercent))
            if clamped != taxRatePercent {
                taxRatePercent = clamped
                return
            }
            UserDefaults.standard.set(taxRatePercent, forKey: Self.taxRateKey)
        }
    }

    /// Convenience: returns the tax in cents for a given subtotal under the
    /// current settings. Returns 0 if tax is disabled or the rate is 0.
    public func taxCents(forSubtotalCents subtotalCents: Int) -> Int {
        guard taxEnabled, taxRatePercent > 0, subtotalCents > 0 else { return 0 }
        let cents = Double(subtotalCents) * taxRatePercent / 100.0
        return Int(cents.rounded())
    }

    /// When ON, the review sheet shows the three preset percentages + a
    /// Custom keypad + No tip option. When OFF, the tip row is hidden
    /// entirely and `tipCents = 0` is always sent through.
    public var tipEnabled: Bool {
        didSet { UserDefaults.standard.set(tipEnabled, forKey: Self.tipEnabledKey) }
    }

    /// Which surcharge policy the demo should send on every charge.
    /// See `SurchargeMode` for what each value means.
    public var surchargeMode: SurchargeMode {
        get { SurchargeMode(rawValue: surchargeModeRaw) ?? .accountDefault }
        set { surchargeModeRaw = newValue.rawValue }
    }

    /// Percentage used when `surchargeMode == .overridePercent`. Clamped
    /// to 0…100 on set. Defaults to 3.0 which is the typical card-network
    /// cap.
    public var surchargeOverrideRatePercent: Double {
        didSet {
            let clamped = max(0, min(100, surchargeOverrideRatePercent))
            if clamped != surchargeOverrideRatePercent {
                surchargeOverrideRatePercent = clamped
                return
            }
            UserDefaults.standard.set(surchargeOverrideRatePercent,
                                      forKey: Self.surchargeOverrideRateKey)
        }
    }

    /// Build the `PaymentBreakdown.Surcharge?` we should send on the
    /// outgoing `processSale` call. The PinPadViewModel calls this for
    /// every sale so the active mode is honored.
    public func surchargeForSale() -> PaymentBreakdown.Surcharge? {
        switch surchargeMode {
        case .accountDefault:
            return nil
        case .disabled:
            return PaymentBreakdown.Surcharge(amount: nil, percentage: nil, bypass: true)
        case .overridePercent:
            // Override is explicit — send the rate verbatim, including 0.
            // (0% means "charge zero surcharge", not account default.)
            guard surchargeOverrideRatePercent >= 0 else { return nil }
            return PaymentBreakdown.Surcharge(
                amount: nil,
                percentage: surchargeOverrideRatePercent,
                bypass: false
            )
        }
    }

    /// The override surcharge in cents for a given base amount (subtotal +
    /// tax + tip), or 0 when the active mode isn't a fixed-rate override or
    /// the rate is 0. Mirrors the surcharge math in
    /// `KoardMerchantService.processSale` so the checkout UI can show — and
    /// the preauth amount can include — the surcharge before it's charged.
    public func overrideSurchargeCents(forBaseCents baseCents: Int) -> Int {
        guard surchargeMode == .overridePercent,
              surchargeOverrideRatePercent > 0,
              baseCents > 0 else { return 0 }
        let cents = Double(baseCents) * surchargeOverrideRatePercent / 100.0
        return Int(cents.rounded())
    }

    /// Three preset tip percentages (e.g. 15 / 18 / 20). Each clamped to
    /// 0…100 on set. The order matches their visual order in the review
    /// sheet.
    public var tipPresets: [Double] {
        didSet {
            // Always keep exactly three entries — the sheet is hardcoded
            // to 3 chips so anything else is a programming error.
            let normalized = (tipPresets + Array(repeating: 0.0, count: 3))
                .prefix(3)
                .map { max(0, min(100, $0)) }
            if Array(normalized) != tipPresets {
                tipPresets = Array(normalized)
                return
            }
            UserDefaults.standard.set(tipPresets, forKey: Self.tipPresetsKey)
        }
    }

    // Underlying @AppStorage-backed strings. Observable so the UI updates.
    private var checkoutModeRaw: String {
        didSet { UserDefaults.standard.set(checkoutModeRaw, forKey: Self.checkoutModeKey) }
    }

    private var appearanceRaw: String {
        didSet { UserDefaults.standard.set(appearanceRaw, forKey: Self.appearanceKey) }
    }

    private var surchargeModeRaw: String {
        didSet { UserDefaults.standard.set(surchargeModeRaw, forKey: Self.surchargeModeKey) }
    }

    private static let checkoutModeKey = "demo.checkoutMode"
    private static let appearanceKey = "demo.appearance"
    private static let taxEnabledKey = "demo.taxEnabled"
    private static let taxRateKey = "demo.taxRatePercent"
    private static let tipEnabledKey = "demo.tipEnabled"
    private static let tipPresetsKey = "demo.tipPresets"
    private static let surchargeModeKey = "demo.surchargeMode"
    private static let surchargeOverrideRateKey = "demo.surchargeOverrideRatePercent"

    private init() {
        self.checkoutModeRaw = UserDefaults.standard.string(forKey: Self.checkoutModeKey)
            ?? CheckoutMode.retail.rawValue
        self.appearanceRaw = UserDefaults.standard.string(forKey: Self.appearanceKey)
            ?? AppearanceMode.system.rawValue
        self.taxEnabled = UserDefaults.standard.object(forKey: Self.taxEnabledKey) as? Bool ?? false
        self.taxRatePercent = (UserDefaults.standard.object(forKey: Self.taxRateKey) as? Double)
            ?? 8.25
        self.tipEnabled = UserDefaults.standard.object(forKey: Self.tipEnabledKey) as? Bool ?? true
        // Stored as `[Any]` in defaults — let the downstream `didSet`
        // pad / trim to length 3 if persistence got corrupted somehow.
        let storedPresets = (UserDefaults.standard.array(forKey: Self.tipPresetsKey) as? [Double])
            ?? [15.0, 18.0, 20.0]
        self.tipPresets = Array(
            (storedPresets + [15.0, 18.0, 20.0])
                .prefix(3)
                .map { max(0, min(100, $0)) }
        )
        self.surchargeModeRaw = UserDefaults.standard.string(forKey: Self.surchargeModeKey)
            ?? SurchargeMode.accountDefault.rawValue
        self.surchargeOverrideRatePercent =
            (UserDefaults.standard.object(forKey: Self.surchargeOverrideRateKey) as? Double)
            ?? 3.0
    }
}
