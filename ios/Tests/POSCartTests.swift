import Testing
@testable import RegisterModels

@Suite("Register money and ticket behavior")
struct POSCartTests {
    @Test func repeatedItemsAndQuantityEditsUseIntegerCents() {
        var cart = POSCart()
        let latte = POSMenuItem.sampleMenu.first { $0.id == "latte" }!
        let outcome1 = cart.add(latte)
        #expect(outcome1)
        let outcome2 = cart.add(latte)
        #expect(outcome2)
        #expect(cart.lines.count == 1)
        #expect(cart.itemCount == 2)
        #expect(cart.subtotalCents == 1100)
        cart.changeQuantity(lineID: latte.id, by: -1)
        #expect(cart.subtotalCents == 550)
        cart.changeQuantity(lineID: latte.id, by: -1)
        #expect(cart.lines.isEmpty)
        #expect(cart.subtotalCents == 0)
    }

    @Test func customAmountsAreSeparateAndCannotExceedTheEntryLimit() {
        var cart = POSCart(maximumCents: 1000)
        let outcome3 = cart.addCustomAmount(0)
        #expect(!outcome3)
        let outcome4 = cart.addCustomAmount(-1)
        #expect(!outcome4)
        let outcome5 = cart.addCustomAmount(400)
        #expect(outcome5)
        let outcome6 = cart.addCustomAmount(600)
        #expect(outcome6)
        #expect(cart.lines.count == 2)
        #expect(Set(cart.lines.map(\.id)).count == 2)
        #expect(cart.subtotalCents == 1000)
        let outcome7 = cart.addCustomAmount(1)
        #expect(!outcome7)
        cart.changeQuantity(lineID: cart.lines[0].id, by: 1)
        #expect(cart.subtotalCents == 1000)
    }

    @Test func failedItemAddPreservesTheExistingTicket() {
        var cart = POSCart(maximumCents: 600)
        let latte = POSMenuItem.sampleMenu.first { $0.id == "latte" }!
        let outcome8 = cart.add(latte)
        #expect(outcome8)
        let before = cart
        let outcome9 = cart.add(latte)
        #expect(!outcome9)
        #expect(cart == before)
        cart.changeQuantity(lineID: "missing", by: -1)
        #expect(cart == before)
        cart.clear()
        #expect(cart.itemCount == 0)
    }

    @Test func followupAmountsDistinguishZeroFromInvalidInput() {
        #expect(TransactionAmountInput.cents(from: "0") == 0)
        #expect(TransactionAmountInput.cents(from: "0.00") == 0)
        #expect(TransactionAmountInput.cents(from: "12.34") == 1234)
        #expect(TransactionAmountInput.cents(from: "12,34") == 1234)
        #expect(TransactionAmountInput.cents(from: ".5") == 50)
        for invalid in ["", "-1", "-0.50", "NaN", "inf", "1e10", "abc", ".", "1.234", "1,234.00", String(Int.max)] {
            #expect(TransactionAmountInput.cents(from: invalid) == nil)
        }
    }

    @Test func keypadAndTicketLimitsAgree() {
        let amount = PinPadAmount(cents: PinPadAmount.maxCents + 1)
        #expect(amount.cents == PinPadAmount.maxCents)
        #expect(PinPadAmount(cents: -1).isZero)
        var entry = PinPadAmount()
        for digit in [1, 2, 3, 4] { entry.append(digit: digit) }
        #expect(entry.cents == 1234)
        entry.backspace()
        #expect(entry.cents == 123)
        #expect(POSCart(maximumCents: PinPadAmount.maxCents).maximumCents == PinPadAmount.maxCents)
    }
}
