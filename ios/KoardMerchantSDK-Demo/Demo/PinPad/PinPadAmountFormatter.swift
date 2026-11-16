import Foundation

/// Cents-shift amount entry used by all pin-pad surfaces in the demo.
///
/// The pin-pad displays a currency amount where the **last digit you type is
/// always the cents column**. That matches how every modern POS (Square,
/// Stripe Terminal, Toast) lets a cashier punch in a sale price.
///
/// Example: tapping `1`, `2`, `3` produces `$1.23` (123 cents). Tapping
/// another `4` produces `$12.34` (1234 cents). Backspace shifts the column
/// back the other way.
public struct PinPadAmount: Equatable {
    public private(set) var cents: Int = 0

    /// Hard cap on how big the amount can grow. $999,999.99 — high
    /// enough for B2B sales / event invoices, well below where the
    /// gigantic display starts overflowing.
    public static let maxCents: Int = 99_999_999

    public init() {}

    public init(cents: Int) {
        self.cents = max(0, min(Self.maxCents, cents))
    }

    public mutating func append(digit: Int) {
        guard (0...9).contains(digit) else { return }
        let next = cents * 10 + digit
        if next > Self.maxCents { return }
        cents = next
    }

    public mutating func backspace() {
        cents = cents / 10
    }

    public mutating func clear() {
        cents = 0
    }

    /// Renders as a `$x,xxx.xx` string suitable for a giant display.
    ///
    /// Uses a single cached `NumberFormatter` — creating a new one on every
    /// keystroke was eating ~3-5 ms per render on device, which is what
    /// caused the pin pad to feel laggy under combined keystroke + reader-
    /// state-poll re-renders.
    public var formattedDisplay: String {
        let dollars = Double(cents) / 100.0
        return Self.currencyFormatter.string(from: NSNumber(value: dollars)) ?? "$0.00"
    }

    public var isZero: Bool { cents == 0 }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
