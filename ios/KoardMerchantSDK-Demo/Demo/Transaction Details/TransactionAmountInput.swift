import Foundation

/// Parses an entered dollar amount without treating invalid input as a zero amount.
enum TransactionAmountInput {
    static func cents(from text: String) -> Int? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = input.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "." || $0 == "," })
        guard !input.isEmpty, parts.count <= 2 else { return nil }
        let whole = String(parts[0])
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let digits = whole + fraction
        guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }), fraction.count <= 2 else { return nil }
        guard let dollars = Int(whole.isEmpty ? "0" : whole) else { return nil }
        let (base, overflow) = dollars.multipliedReportingOverflow(by: 100)
        guard !overflow else { return nil }
        let fractionalCents = fraction.isEmpty ? 0 : Int(fraction)! * (fraction.count == 1 ? 10 : 1)
        let (cents, additionOverflow) = base.addingReportingOverflow(fractionalCents)
        return additionOverflow ? nil : cents
    }
}
